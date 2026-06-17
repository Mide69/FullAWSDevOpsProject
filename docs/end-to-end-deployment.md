# End-to-End Deployment — A Step-by-Step Learning Guide
## GovPlatform UK · From an Empty AWS Account to a Running, Secured Platform

> **Who this is for:** someone who wants to understand *how* a production-grade AWS
> platform is built, in the exact order it must happen, and *why* each step exists.
> Every step has three parts: **What** (the action), **The command** (what you run),
> and **Why** (the reasoning). Read it like a recipe that also teaches you to cook.

> **The golden rule that recurs throughout:** *verify, don't trust.* After every
> create or destroy, we check reality (the AWS API or `kubectl`), never just the
> exit code. You will see why this matters more than once.

---

## The Big Picture — what we are building and the order

You cannot build this in any order. Each layer sits on the one below it. This is the
**dependency order**, and it is the spine of the whole guide:

```
0. Account foundation      (Control Tower, SSO)         ── governance first
1. Terraform backend       (S3 + DynamoDB)              ── so IaC can store state
2. Network                 (VPC, subnets, NAT)          ── everything lives inside it
3. Registry                (ECR)                        ── somewhere for images
4. Compute                 (EKS + IRSA)                 ── runs the containers
5. The app                 (build → push → deploy)      ── first proof of life
6. Public access           (ALB via Ingress)            ── reachable from internet
7. State + secrets         (RDS + Secrets Manager)      ── durable data, safely
8. The other services      (claim, case, document)      ── platform proves multi-tenant
9. Security plane          (WAF, GuardDuty, etc.)       ── defence + detection
10. Observability          (Container Insights, alarms) ── see what's happening
11. CI/CD                  (GitHub Actions OIDC)        ── automate the whole loop
12. Teardown               (destroy, verified)          ── stop paying when idle
```

**Why this order?** You build the ground before the building. A VPC must exist before
EKS can place nodes in it. EKS must exist before a pod can run. A pod must run before a
load balancer has anything to route to. Get the order wrong and every step becomes
debugging instead of building.

---

# PHASE 0 — Account Foundation

## Step 0.1 — Multi-account landing zone with Control Tower
**What:** Set up AWS Control Tower in the management account; let it create a
multi-account organisation with a dedicated **workload account** for the platform.

**Why:** You never run real workloads in your root/management account. Separate
accounts contain the **blast radius** — if one is compromised or you fat-finger a
delete, the damage is bounded. Control Tower automates creating these accounts *with
security guardrails already applied*, instead of you configuring each by hand.

**Key concepts:**
- **Organisational Unit (OU)** — a folder of accounts that share policy. We use a
  `GovPlatform` OU containing the `govplatform-dev` account.
- **Service Control Policies (SCPs)** — org-wide rules that cap what an account can do,
  *even for its administrators*. Ours deny root usage, block disabling CloudTrail/
  GuardDuty, and restrict to UK regions (eu-west-2/eu-west-1). An SCP is a **ceiling**;
  an IAM policy is a **grant**. Effective permission = grant ∩ (not denied by SCP).

## Step 0.2 — Access via IAM Identity Center (SSO), never IAM users
**What:** Create an SSO user, an `AdministratorAccess` permission set, and assign it to
the `govplatform-dev` account.

**Why:** Traditional IAM users have **long-lived access keys**. If a key leaks (e.g.
committed to GitHub), an attacker has lasting access. SSO issues **temporary**
credentials that expire (~8 hours), so there is no permanent key to steal.

**The command (configure your laptop's CLI):**
```bash
aws configure sso
#   SSO start URL: https://ssoins-xxxx.portal.eu-west-2.app.aws
#   SSO region:    eu-west-2
#   profile name:  govplatform-dev
aws sso login --profile govplatform-dev
aws sts get-caller-identity --profile govplatform-dev
```
**Why the last line matters (verify, don't trust):** the ARN you get back should look
like `arn:aws:sts::445358171352:assumed-role/AWSReservedSSO_.../you` — note `sts`
(temporary) and `assumed-role` (federated), proving you are NOT using a static IAM
user. If you see `:user/`, you are on the wrong credentials.

> **Real lesson:** during the build we found old long-lived keys for a forgotten IAM
> user sitting on the laptop. Deleting the local file is *not* remediation — the key
> still works from anywhere. You must **revoke at the source** (delete the key/user in
> IAM). Same logic as responding to a leaked credential.

---

# PHASE 1 — Terraform Backend (the bootstrap)

## Step 1.1 — Create the state bucket and lock table
**What:** Create an S3 bucket (versioned, encrypted, private) for Terraform state and a
DynamoDB table for state locking — using a **one-off script**, not Terraform.

**Why (the bootstrap problem):** Terraform stores its memory of what it built in a
**state file**. That file should live remotely (in S3) so it's shared, durable, and
recoverable. But Terraform needs the bucket to exist *before* it can run — a
chicken-and-egg. So these two resources are the only ones created outside Terraform.
Everything else is Terraform-managed.

**The command:**
```bash
./infrastructure/terraform/bootstrap/bootstrap.sh
```
This creates `govplatform-tfstate-<account>` (S3) and `govplatform-tflock` (DynamoDB).

**Why each setting:**
- **Versioning** — state is the single source of truth; if it's corrupted or deleted,
  you can roll back to a previous version.
- **Encryption** — state files can contain sensitive values in plain text.
- **Block all public access** — leaked state buckets are a top cause of real breaches.
- **DynamoDB lock** — before any `apply`, Terraform writes a lock row. A second
  simultaneous `apply` sees the lock and refuses to start, preventing two people from
  corrupting state at once. (If a run crashes mid-apply, clear a stale lock with
  `terraform force-unlock <id>` — but only after confirming nobody is really running.)

## Step 1.2 — Understand the Terraform workflow you'll repeat forever
```
write/edit .tf  →  terraform init   (once per new module/provider/backend)
                →  terraform validate (syntax + consistency)
                →  terraform plan     (DRY RUN — read it every time)
                →  terraform apply     (make reality match; type 'yes')
                →  terraform destroy   (tear it all down)
```
**Why read the plan, always:** the plan shows `+` create, `-` destroy, `~` change, and
the dangerous **`-/+` replace** (destroy-and-recreate). On a database, a replace means
deleting your data. The plan is your last checkpoint before reality changes.

**Repo structure and why:**
```
infrastructure/terraform/
├── modules/        ← reusable building blocks (vpc, eks, ecr, rds, irsa…)
└── environments/dev/ ← calls modules with dev-specific values
```
**Modules define shape; environments supply numbers.** Prod will reuse the *same*
modules with different values — consistency by construction, not by discipline.

---

# PHASE 2 — Network (VPC)

## Step 2.1 — A 3-tier, 3-AZ VPC
**What:** A VPC (`10.0.0.0/16`) across three Availability Zones, each with three subnet
tiers: public, private, data. Plus an Internet Gateway, NAT, and VPC Flow Logs.

**The command:**
```bash
cd infrastructure/terraform/environments/dev
terraform init
terraform plan      # read it: ~31 resources to add
terraform apply
```

**Why three tiers (security — defence against attackers):**
| Tier | Reachable from | Holds |
|------|----------------|-------|
| Public | the internet | the load balancer only |
| Private | the public tier | the application pods |
| Data | the private tier | the database |
The **data tier has no internet route at all** — even a fully compromised database
cannot "phone home". Enforced by routing, not just firewalls.

**Why three AZs (availability — defence against disasters):** a subnet lives in exactly
one AZ (one physical data centre). Spreading across three means any one can fail and the
platform survives. 3 tiers × 3 AZs = 9 subnets.

**Why a NAT gateway:** private pods sometimes need outbound internet (pull an update);
NAT is a **one-way door** — out is allowed, in is impossible. (Dev uses one NAT to save
~£70/month; prod uses one per AZ for HA. It's a single config flag in our module.)

**Why VPC Flow Logs:** a record of every network connection, for security
investigation. A government compliance expectation.

## Step 2.2 — Verify (don't trust)
```bash
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>" \
  --query "Subnets[].{Name:Tags[?Key=='Name']|[0].Value,CIDR:CidrBlock,AZ:AvailabilityZone}" \
  --output table --profile govplatform-dev --region eu-west-2
```
You should see 9 subnets, three tiers × three AZs, matching your CIDR plan.

---

# PHASE 3 — Container Registry (ECR)

## Step 3.1 — One repository per service
**What:** ECR repos for each service, with immutable tags and scan-on-push.

**Why before compute:** the cluster is useless with nothing to run, and ECR has no
dependencies — a quick, safe win. **Immutable tags** mean an image tag (we use the git
commit SHA) can never point to different content: what you tested is what you deploy.
**Scan on push** checks each image for known vulnerabilities (CVEs).

> **Lesson — "enabled" ≠ "ran":** the default `docker buildx` build pushes an OCI image
> *index with attestations*, which ECR **basic** scanning silently skips (you'll see
> `imageDigest: null`). So scan-on-push being enabled does not prove an image was
> scanned. Verify the findings exist, or use Inspector v2 enhanced scanning.

---

# PHASE 4 — Compute (EKS + IRSA)

## Step 4.1 — A managed Kubernetes cluster with Spot nodes
**What:** An EKS cluster (`dev-govplatform`), a managed node group on **Spot**
instances, and an **OIDC provider** for IRSA.

**The command:** `terraform apply` (control plane ~9 min, nodes ~3 min).

**Why EKS:** Kubernetes is the automated operations manager for containers — it keeps N
copies running, restarts crashes, reschedules pods when a node dies. **EKS** means AWS
runs the hard part (the control plane / "brain") for you.

**Why Spot nodes:** ~70% cheaper spare capacity that AWS can reclaim with 2 minutes'
notice; Kubernetes simply reschedules the pods. Ideal for dev.

**Why three IAM roles appear:** every AWS service that acts on your behalf needs a role
whose **trust policy** says who may wear it:
- the **cluster** role (`Principal: eks.amazonaws.com`) — EKS manages network interfaces
- the **node** role (`Principal: ec2.amazonaws.com`) — nodes join the cluster, pull from
  ECR, write logs
- the **OIDC provider** — the foundation of IRSA (next).

## Step 4.2 — Connect kubectl and verify
```bash
aws eks update-kubeconfig --name dev-govplatform --region eu-west-2 --profile govplatform-dev
kubectl get nodes      # expect 2 Ready nodes, in private-subnet IPs across 2 AZs
```

## Step 4.3 — IRSA: a unique IAM identity per pod (the #1 EKS security concept)
**What:** IAM Roles for Service Accounts — each pod assumes its *own* IAM role instead
of borrowing the node's permissions.

**Why:** without it, every pod on a node shares the node's permissions, so a compromised
pod gets everything. IRSA gives each pod *only* what it needs.

**How it works — the two-half handshake:**
1. **IAM side (Terraform):** a role whose trust policy allows assumption *only* by a
   specific `namespace/serviceaccount`, verified through the cluster's OIDC provider.
2. **Kubernetes side:** that ServiceAccount is *annotated* with the role's ARN.
When the pod calls AWS, it presents its service-account token; AWS verifies it via OIDC
and issues temporary credentials. **No static keys, ever.**

---

# PHASE 5 — Build and Deploy the First Service

## Step 5.1 — Run it locally first
**Why:** if you cannot run it on your laptop, you cannot debug it in AWS. Docker Compose
/ `npm start` is the fastest feedback loop.
```bash
cd app && npm install && npm start
curl http://localhost:3000/health     # in a second terminal
```

## Step 5.2 — Containerise it (the Dockerfile choices)
**Why each line:**
- **Multi-stage build** — a builder stage installs dependencies; a fresh runtime stage
  copies only what's needed, so build tools never reach production.
- **Alpine base** — tiny image, smaller attack surface.
- **Non-root user with a NUMERIC UID** — see the lesson below.
- **HEALTHCHECK** — the container reports if it's alive.

## Step 5.3 — Build, scan locally, push to ECR (immutable tag = git SHA)
```bash
SHA=$(git rev-parse --short HEAD)
ECR=<acct>.dkr.ecr.eu-west-2.amazonaws.com
aws ecr get-login-password --region eu-west-2 --profile govplatform-dev | docker login --username AWS --password-stdin $ECR
docker build -f containers/Dockerfile -t $ECR/govplatform/user-service:$SHA .
docker push $ECR/govplatform/user-service:$SHA
# VERIFY it actually landed:
aws ecr describe-images --repository-name govplatform/user-service --image-ids imageTag=$SHA --region eu-west-2 --profile govplatform-dev --query "imageDetails[].imageTags"
```
> **Lesson — Docker can fail silently:** during the build, Docker Desktop was off, so
> `docker build`/`push` failed but the script marched on, leaving a manifest pointing at
> a nonexistent image. **Always verify the image is in ECR** before deploying.

## Step 5.4 — Deploy to Kubernetes (Deployment + Service)
**Why two objects:**
- **Deployment** — "run 2 replicas of this image; here's how to health-check them". It
  also performs **rolling updates**: new healthy pods come up *before* old ones are
  removed → zero downtime.
- **Service (ClusterIP)** — one stable internal address; pods come and go with changing
  IPs, the Service is the steady front door. Routing is by **labels**, not IPs.

**The pod settings and why:**
- **livenessProbe** ("alive?") → fail restarts the pod. **readinessProbe** ("ready for
  traffic?") → fail removes it from the Service (no restart).
- **requests/limits** — requests are guaranteed (scheduling); limits are the hard
  ceiling (exceed memory → OOMKilled). One service can't starve others.
- **securityContext** — non-root, no privilege escalation, read-only root filesystem,
  all capabilities dropped. Defence in depth.

> **Lesson — read the actual error:** the first deploy failed with
> `CreateContainerConfigError`. `kubectl describe pod` revealed: *"runAsNonRoot and
> image has non-numeric user (appuser)"*. Kubernetes must verify non-root *before*
> starting, and can't resolve a username to a UID. **Fix:** create the user with a
> numeric UID in the Dockerfile (`adduser -u 10001`) and set `runAsUser: 10001`. Because
> the image changed, the immutable-tag rule forced a new commit → new SHA → new image.

```bash
kubectl apply -f k8s/user-service/
kubectl get pods            # both Running, 1/1
```

---

# PHASE 6 — Public Access (ALB via Ingress)

## Step 6.1 — Install the AWS Load Balancer Controller (Helm)
**What:** A controller that watches for Ingress objects and builds a real ALB.

**The command (note the explicit vpcId):**
```bash
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system -f k8s/platform/lbc-values.yaml \
  --set vpcId=$(terraform -chdir=infrastructure/terraform/environments/dev output -raw vpc_id)
```
**Why Helm:** a package manager for Kubernetes. Use **plain manifests for your own
apps** (you own/review them) and **Helm for third-party components** (versioned,
repeatable installs). The controller needs ~15 inter-related objects — let its chart
manage them.

> **Lesson — explicit config beats auto-discovery:** we first omitted `vpcId` thinking
> the controller would auto-discover it. It crashed (`CrashLoopBackOff`) because EKS
> pods can't reach EC2 instance metadata (IMDS) by default. **Pass `vpcId` explicitly**
> from Terraform output. Auto-discovery that depends on network a pod may not have is a
> trap.

## Step 6.2 — The Ingress (declare intent, a controller makes it real)
**Why:** an **Ingress** is a *declaration*: "I want a public HTTP route to this
service." The controller turns it into an ALB in the public subnets, routing to your
pods. This is the Kubernetes **operator pattern** — declare desired state, a controller
reconciles reality.
```bash
kubectl apply -f k8s/platform/ingress.yaml
kubectl get ingress -w          # wait for the ...elb.amazonaws.com ADDRESS
curl http://<alb-address>/health
```

---

# PHASE 7 — Durable State (RDS + Secrets Manager)

## Step 7.1 — PostgreSQL in the data tier, password auto-managed
**What:** An RDS PostgreSQL instance in the data subnets, reachable only from the EKS
cluster's security group, with `manage_master_user_password = true`.

**Why that flag is the elegant bit:** RDS itself **creates and rotates** the master
password directly in **Secrets Manager**. The password therefore **never appears in your
Terraform code or state**, and no human ever sees it.

**Why the security group:** it allows port 5432 *only* from the EKS cluster security
group — not the internet, not the rest of the VPC. The database accepts connections
exclusively from your pods.

## Step 7.2 — Give the pod least-privilege access to the secret (IRSA again)
**What:** An IRSA role for `user-service` scoped to read **exactly one** secret ARN.
```hcl
actions   = ["secretsmanager:GetSecretValue"]
resources = [module.rds.master_user_secret_arn]   # one ARN, not "*"
```
**Why:** least privilege, literally. The pod can read that one secret and nothing else.

## Step 7.3 — The app fetches credentials at runtime
**Why this design (config vs secrets separation):**
- **ConfigMap** holds *non-secret* config — DB host, name, and the secret's *ARN* (an
  address, not the secret).
- The **secret** (password) stays in Secrets Manager and is fetched at startup using the
  pod's IRSA identity (the AWS SDK picks it up automatically — no keys in code).

**Why a deploy script:** the DB host and secret ARN **change on every rebuild**, but the
IAM role name is **stable**. So the stable bit (role ARN) is hardcoded in the
ServiceAccount manifest, and the changing bits are read from `terraform output` and
injected via a ConfigMap by `scripts/deploy-user-service.sh` — exactly what a CI/CD
pipeline does.

## Step 7.4 — Prove persistence
```bash
curl -X POST http://<alb>/users -d '{"name":"Ada","email":"ada@gov.uk"}' -H 'Content-Type: application/json'
kubectl delete pods -l app=user-service          # destroy the pods
kubectl rollout status deployment/user-service
curl http://<alb>/users                          # Ada is STILL there
```
**Why this proves the platform:** brand-new containers replaced the old ones, yet the
data survived — because it lives in RDS, not in the pod. Stateless compute, durable
state.

---

# PHASE 8 — The Other Three Services

Each follows the **same pattern** as user-service, with one distinguishing trait — which
is the whole point: the platform supports diverse tenants on one set of primitives.

| Service | Distinct trait | Extra AWS resource | Extra IRSA permission |
|---------|----------------|--------------------|-----------------------|
| **claim-service** | event-driven | SQS queue | `sqs:SendMessage` to that queue |
| **case-service** | **internal-only** | none | DB secret only |
| **document-service** | secure file upload | S3 bucket | S3 read/write on that bucket |

**Why case-service has no Ingress:** it is `ClusterIP` only — reachable solely by other
pods via internal DNS (`case-service.default.svc.cluster.local`), never from the
internet. This **demonstrates network segmentation**: some services must never be
publicly reachable, and the architecture *enforces* it rather than relying on a firewall
rule someone might misconfigure.

**Why document-service uses S3 pre-signed URLs:** the citizen uploads the file directly
to S3 using a short-lived URL the service generates; the service never handles the file
bytes. Faster, cheaper, and the file never transits the app.

**One Dockerfile for all:** a `SERVICE_PATH` build-arg selects which service to build —
DRY, one place to maintain the build/security settings.

**Deploy everything at once:**
```bash
./scripts/deploy-all.sh    # builds+pushes 4 images, generates config, applies all manifests
```

---

# PHASE 9 — Security Plane

**What:** WAF on the ALB plus account-wide threat detection.
```bash
terraform apply   # adds the WAF + GuardDuty + Security Hub + Inspector
```
- **WAF (Web Application Firewall)** — attached to the ALB; AWS-managed OWASP rule sets
  (common exploits, known-bad inputs) plus **rate limiting** (block an IP over 2000
  req / 5 min). *Why:* stops common attacks before they reach a pod.
- **GuardDuty** — continuous threat detection from logs/DNS/network. *Why:* spots
  compromised credentials, crypto-mining, reconnaissance automatically.
- **Security Hub** — aggregates findings and scores you against the Foundational
  Security Best Practices standard. *Why:* one compliance dashboard.
- **Inspector v2** — continuous CVE scanning of ECR images and EC2. *Why:* the *enabled*
  enhanced scan that actually runs (unlike basic scan-on-push).

**Production delta (documented, not built here):** HTTPS via an ACM certificate + an
HTTPS-redirect listener, and UK geo-restriction on the WAF — these need a domain you
control for certificate validation.

---

# PHASE 10 — Observability

**What:** Container Insights (metrics + container logs), a CloudWatch dashboard, alarms,
and an SNS email topic.
```bash
terraform apply   # enables the amazon-cloudwatch-observability addon + dashboard + alarms
```
- **Container Insights** — full cluster/pod metrics and logs into CloudWatch. The
  CloudWatch agent uses the **node role** (we attach `CloudWatchAgentServerPolicy`).
- **Alarms → SNS → email** — node CPU > 80% for 15 min, or pods restarting repeatedly.
  *Why:* you find out about problems before users do. (Confirm the SNS subscription email
  AWS sends you.)
- **Dashboard** — one pane: node CPU/memory, running pod count.

**Why this is "won or lost at senior level":** anyone can deploy; operating means being
able to answer *"what happened between 14:00 and 14:05 yesterday?"* using metrics, logs,
and traces.

---

# PHASE 11 — CI/CD (GitHub Actions via OIDC)

## Step 11.1 — Trust GitHub without storing keys
**What:** A GitHub OIDC provider + an IAM role GitHub Actions can assume, scoped to *this
repo's main branch only*, plus an **EKS access entry** granting it deploy rights in the
`default` namespace.
```bash
terraform apply   # creates the OIDC provider, dev-github-actions role, EKS access entry
```
**Why OIDC:** traditional CI stores long-lived AWS keys as secrets — a leak risk. With
OIDC, GitHub presents a short-lived signed token; AWS trusts it and issues **temporary**
credentials, but only for the configured repo/branch. **No keys stored in GitHub.**

**Why the trust condition matters:**
```
token.actions.githubusercontent.com:sub = repo:Mide69/FullAWSDevOpsProject:ref:refs/heads/main
```
Only the main branch of *your* repo can assume the role — not a fork, not another repo.

**Why an EKS access entry:** the modern replacement for editing the `aws-auth`
ConfigMap. It maps the CI IAM role to Kubernetes RBAC (`AmazonEKSEditPolicy`, scoped to
`default`) so the pipeline can `kubectl set image` but nothing more.

## Step 11.2 — The pipeline (`.github/workflows/deploy.yml`)
On every push to `main` that touches app/service/container/k8s code:
1. **Assume the role via OIDC** (`permissions: id-token: write`).
2. **Build** each service image (matrix over the 4 services).
3. **Scan with Trivy** (CRITICAL/HIGH) — report, optionally block.
4. **Push** to ECR with the git-SHA tag.
5. **Deploy** — `kubectl set image` for each deployment, then `rollout status`.

**Why a separate `deploy` job that `needs` the build:** you don't deploy anything until
*all* images built and scanned successfully. Gate first, deploy second.

---

# PHASE 12 — Teardown (and why order matters)

**What:** Destroy everything to stop paying when idle — and rebuild on demand.

## Step 12.1 — Delete Ingresses FIRST
```bash
kubectl delete ingress --all -A
# wait ~45s, then confirm no ALBs remain
aws elbv2 describe-load-balancers --region eu-west-2 --profile govplatform-dev --query "LoadBalancers[].LoadBalancerName"
```
**Why:** the ALB was created by the *controller*, not Terraform, so Terraform doesn't
know to delete it. If you destroy the cluster first, the ALB **orphans** — it keeps
billing *and* its network interfaces block the VPC from deleting.

## Step 12.2 — Destroy
```bash
cd infrastructure/terraform/environments/dev
terraform destroy -auto-approve
```
> **Lesson — ECR won't delete a non-empty repo.** Terraform errors with
> `RepositoryNotEmptyException` and stops before finishing the VPC. Empty the repo first
> (`aws ecr batch-delete-image ... --image-ids "$(aws ecr list-images ...)"`), then
> re-run destroy. (Or set `force_delete = true` on the repo.)

## Step 12.3 — VERIFY by API (never trust the exit code)
```bash
for check in \
  "eks list-clusters --query clusters" \
  "rds describe-db-instances --query DBInstances[].DBInstanceIdentifier" \
  "ec2 describe-nat-gateways --filter Name=state,Values=available --query NatGateways[].NatGatewayId" \
  "elbv2 describe-load-balancers --query LoadBalancers[].LoadBalancerName" ; do
  echo "$check"; done
# (run each as: aws <service> <args> --region eu-west-2 --profile govplatform-dev)
```
> **The most important lesson of the whole project:** a `terraform destroy` once exited
> with code 0 while resources were *still running and billing* (the exit code came from
> a pipe, and an earlier init had failed). Only a direct API scan caught it. **Verify
> the world, not the tool's say-so.**

**What you intentionally keep:** the Terraform **state bucket** and **lock table** (a few
pennies/month — the backbone for the next rebuild), and the **Control Tower baseline**
(default VPC, SSO, guardrails — free/managed, not yours to delete).

---

# The Rebuild Runbook (the daily loop)

Because it's all IaC, the entire platform comes back with:
```bash
aws sso login --profile govplatform-dev
cd infrastructure/terraform/environments/dev && terraform apply        # ~15 min
aws eks update-kubeconfig --name dev-govplatform --region eu-west-2 --profile govplatform-dev
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system -f ../../../../k8s/platform/lbc-values.yaml \
  --set vpcId=$(terraform output -raw vpc_id)
cd ../../../.. && ./scripts/deploy-all.sh
```
**Why this is the ultimate proof:** rebuilding from an empty account on demand proves the
Infrastructure as Code is *complete* — nothing was done by hand and forgotten. That
single fact is the strongest thing you can say about an IaC platform.

---

# The Recurring Themes (what to actually remember)

1. **Dependency order** — network → registry → compute → app → ingress → data. Each
   layer needs the one below.
2. **Verify, don't trust** — check the AWS API / `kubectl`, never the exit code. It saved
   us on a silent Docker failure, a fake-success destroy, and an unscanned image.
3. **No long-lived keys anywhere** — SSO for humans, IRSA for pods, OIDC for CI. Every
   credential is temporary.
4. **Least privilege, literally** — SCPs cap the account; IRSA scopes each pod to exactly
   what it needs (one secret ARN, one queue, one bucket).
5. **Defence in depth** — SCPs, 3-tier subnets with an isolated data tier, security
   groups, non-root read-only containers, WAF, GuardDuty — many layers, not one wall.
6. **Reproducibility** — modules define shape, environments supply numbers; destroy and
   rebuild on demand; immutable image tags tie every running container to exact source.
7. **Cost is an engineering input** — single NAT, Spot nodes, single-AZ DB in dev; each
   is a config flag flipped for prod. A senior engineer can always state what a design
   costs.
