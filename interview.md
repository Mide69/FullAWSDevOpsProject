# Interview Preparation — Deploying & Managing an End-to-End Project
## GovPlatform UK · STAR Method · UK Civil Service

> **How to use this document**
> The first section is your spoken STAR answer — what you actually say in the room.
> Everything after it is a textbook: it explains every service, every decision, and
> every term, so that if an interviewer drills into *any* part, you can go deeper with
> total confidence. Read it end to end at least twice. By the second read, the
> vocabulary becomes yours.

---

# PART 1 — THE STAR ANSWER (what you say)

The UK Civil Service STAR format = **S**ituation, **T**ask, **A**ction, **R**esult.
Keep Situation and Task short. Spend most of your time on Action (that's where they
score your competence). Always finish with a measurable Result.

> **Likely question:** *"Tell me about a time you deployed and managed an end-to-end
> project. What did you do, and what was the outcome?"*

## Situation (≈20 seconds)
> "Government development teams repeatedly waste weeks setting up cloud infrastructure
> before they can ship a service, and every team does it differently — which creates
> inconsistent security and makes audits painful. I set out to build **GovPlatform**,
> a secure, standardised AWS platform on which teams could deploy digital services
> quickly and safely, modelled on how a department like DWP actually operates."

## Task (≈20 seconds)
> "My responsibility was to design, build, deploy, and operate the whole thing end to
> end — the multi-account AWS foundation, the network, the container platform, the
> CI/CD pipeline, the database layer, security controls, and monitoring — all as
> reproducible Infrastructure as Code, not click-ops. It had to be something I could
> destroy and rebuild from scratch on demand, and hand over to another engineer."

## Action (the bulk — ≈2-3 minutes)
> "I worked in dependency order, building each layer on the one beneath it.
>
> **First, the account foundation.** I used **AWS Control Tower** to create a
> multi-account landing zone with a dedicated workload account, governed by **Service
> Control Policies** — for example, blocking root-account use and restricting the
> platform to UK regions. Access was through **IAM Identity Center** single sign-on
> with temporary credentials only — no long-lived IAM users anywhere.
>
> **Then the network**, written as **Terraform** modules. A **VPC** spanning three
> Availability Zones, with three subnet tiers — public for the load balancer, private
> for the application, and a data tier for the database with no internet route at all.
> This gives me defence in depth against attackers and fault tolerance against an AZ
> failure on two separate axes.
>
> **Next, the container platform.** I provisioned an **Amazon EKS** Kubernetes cluster
> with Spot worker nodes for cost, and set up **IRSA** so that every pod gets its own
> least-privilege IAM identity rather than sharing the node's. I built the application
> as a container — multi-stage Docker build, non-root user, vulnerability-scanned —
> pushed it to **ECR** with an immutable git-SHA tag for traceability, and deployed it
> to EKS with health probes, resource limits, and a locked-down security context.
>
> **Then I exposed it safely.** I installed the **AWS Load Balancer Controller** and
> used a Kubernetes **Ingress** to provision an **Application Load Balancer**, giving
> the service a real public endpoint, with the path running internet → ALB → pods.
>
> **Finally, state and secrets.** I added an **RDS PostgreSQL** database in the data
> tier, reachable only from the cluster's security group, with the master password
> created and rotated automatically by **AWS Secrets Manager** — so the credential
> never appeared in my code or Terraform state. The application read it at runtime
> using its own IRSA role, scoped to that single secret.
>
> Throughout, everything was version-controlled in Git, every change went through a
> plan-and-review step, and I could tear the whole platform down and rebuild it with a
> single command."

## Result (≈20 seconds — make it measurable)
> "The outcome was a platform where a service goes from a git commit to running on
> public AWS infrastructure in under 20 minutes, fully reproducibly. Because it's all
> Infrastructure as Code, I rebuilt it from an empty account every single working
> session — which proves the IaC is complete and the disaster-recovery story is real.
> Security was enforced by design — no root usage, no static keys, least-privilege per
> pod, encryption everywhere — and I kept the running cost under control by tearing
> down compute when idle. Most importantly, another engineer could read the repo and
> rebuild it without me."

## If they ask "what would you do differently / improve?"
> "I'd add HTTPS with an ACM certificate and a WAF with OWASP rules and UK
> geo-restriction on the load balancer; move deployments to GitOps with ArgoCD; and
> enable Inspector enhanced scanning and Security Hub for continuous compliance. I'd
> also promote the dev settings to full production values — Multi-AZ database, one NAT
> gateway per AZ — which in my design are single config flags."

---

# PART 2 — THE TEXTBOOK (so you can answer ANY follow-up)

This section explains the *why* behind every choice. Each service gets: what it is in
plain English, what problem it solves, the role it plays here, and the key terms.

## 2.0 The mental model — a secure office building

Hold this picture; every service maps to a part of it:

```
        THE INTERNET  (visitors / citizens)
              │
   🛡️  WAF        — security guard checking for known attacks   (future hardening)
              │
   🏢  ALB        — the receptionist who routes visitors        [public subnets]
              │
   👷  EKS pods   — staff doing the actual work                 [private subnets]
        (your container, each holding its own IRSA "badge",
         fetching the DB password from the Secrets Manager safe)
              │
   🔐  RDS        — the records vault in the basement           [data subnets]

   The whole building sits on a fenced plot (VPC), is built three times in three
   locations (Availability Zones), and the plot itself sits inside a governed estate
   (Control Tower multi-account organisation).
```

---

## 2.1 AWS Control Tower — the governed estate

**What it is:** A service that sets up and governs *multiple* AWS accounts from one
place. It creates a "landing zone" — a pre-secured, multi-account starting point.

**The problem it solves:** Large organisations should not run everything in one AWS
account. If one account is compromised or someone makes a mistake, you want the
"blast radius" contained. But manually creating many accounts and applying the same
security to each is slow and error-prone. Control Tower automates it.

**Its role in GovPlatform:**
- Created an **Organisation** with separate accounts — a management account, security
  accounts (log archive + audit), and a dedicated **workload account** for the platform.
- Organised accounts into **Organisational Units (OUs)** — folders for accounts that
  share a purpose, so policies can be applied to a whole group.
- Applied **guardrails** automatically to every account.

**Key terms:**
- **Landing zone** — the whole pre-configured multi-account environment.
- **Account Factory** — the self-service form that vends a new, fully-governed account
  in ~20 minutes. This is the "teams get an account fast" promise.
- **Blast radius** — how much damage a single failure/compromise can cause. Separate
  accounts shrink it.

**Interview soundbite:** *"Control Tower gives me account vending with security
guardrails applied automatically, so every new team starts compliant by default
instead of compliant-if-they-remember."*

---

## 2.2 Service Control Policies (SCPs) — rules even admins can't break

**What they are:** Organisation-wide rules that set the **maximum** permissions any
account can have. They don't *grant* access; they put a ceiling on it.

**SCP vs IAM policy (a classic interview question):**
- An **IAM policy** *grants* permissions to a user/role *within* an account.
- An **SCP** sets the *boundary* of what's even possible in that account, from above.
- The effective permission is the **intersection**: you can only do something if IAM
  allows it **and** no SCP forbids it. An SCP can stop even an account administrator.

**Their role here:** I used SCPs to enforce non-negotiables — deny root-account use,
prevent disabling CloudTrail/GuardDuty, deny unencrypted S3, and restrict the platform
to UK regions (eu-west-2/eu-west-1). These protect data sovereignty and audit
integrity, which matter enormously in government.

**Interview soundbite:** *"SCPs let me guarantee controls that even a compromised
administrator cannot switch off — that's the difference between policy on paper and
policy enforced."*

---

## 2.3 IAM Identity Center (SSO) — login without long-lived keys

**What it is:** AWS single sign-on. You log in once and get **temporary** credentials
to the accounts and roles you're allowed to use.

**The problem it solves:** Traditional IAM users have long-lived access keys. If a key
leaks (e.g. committed to GitHub), an attacker has lasting access. The fix is to not
have permanent keys at all.

**Its role here:** My only access to the workload account was via SSO — I'd
authenticate, pick the account, pick a role (`AdministratorAccess`), and AWS issued
credentials that **expire after ~8 hours**. Nothing stored on disk.

**How you prove it:** the identity I assumed looked like
`arn:aws:sts::<account>:assumed-role/AWSReservedSSO_.../olamide.kosile` —
note `sts` (temporary) and `assumed-role` (federated), not an IAM user.

**A real lesson from the build:** I found old long-lived keys for a forgotten IAM user
on the machine. The correct remediation isn't deleting the local file — the key still
works from anywhere — it's **revoking at the source** (deleting the user/key in IAM).
Same logic as incident response for a leaked credential.

---

## 2.4 Terraform — Infrastructure as Code

**What it is:** A tool that builds cloud infrastructure from text files. You *describe*
the desired end state; Terraform makes reality match it.

**Declarative, not imperative:** You don't write "create a subnet" (a command you could
accidentally run twice). You write "a subnet exists" (a fact). Run it twice → still one
subnet. This **idempotency** is the whole point.

**How it thinks — the diff engine:** Terraform juggles three things:
- **Code** (`.tf` files) — what you want.
- **State** (`terraform.tfstate`) — what Terraform believes exists.
- **Reality** (AWS) — what actually exists.
`terraform plan` shows the difference; `terraform apply` closes it.

**Key terms & how I used them:**
- **Resource** — one piece of infrastructure (`aws_vpc`, `aws_eks_cluster`).
- **Module** — a reusable folder of resources (my `vpc`, `eks`, `rds`, `irsa` modules).
  Modules define *shape*; environments supply *numbers*. So dev and prod use the same
  modules with different values — consistency by construction.
- **Variables / outputs** — a module's inputs and return values. One module's output
  (e.g. the VPC's subnet IDs) feeds another's input (EKS). These references also tell
  Terraform the build order automatically.
- **Remote state** — I stored state in an **S3 bucket** (versioned + encrypted) with a
  **DynamoDB lock table** so two people can't apply at once and corrupt it.
- **The bootstrap problem** — Terraform needs the state bucket to exist before it can
  run, so the bucket + lock table are the only two resources created by a one-off
  script outside Terraform. Everything else is Terraform-managed.

**Interview soundbite:** *"Everything is reproducible Infrastructure as Code with
remote, locked state — I can destroy and rebuild the entire platform from a clean
account, which is the ultimate test that the code is complete."*

---

## 2.5 VPC & the 3-tier network — the fenced plot

**What a VPC is:** Your own private, isolated network inside AWS. Nothing enters or
leaves except through gateways you define.

**Availability Zones (AZs):** Physically separate data centres within a region. A
subnet lives in exactly one AZ. To survive a data-centre failure, you replicate across
several. I used **three**.

**The three subnet tiers (why three, not two):**
| Tier | Who can reach it | What lives there |
|------|------------------|------------------|
| **Public** | The internet | The load balancer only |
| **Private** | Only the public tier | The EKS pods (app code) |
| **Data** | Only the private tier | RDS (the database) |

The **data tier has no internet route at all** — even a fully compromised database
cannot "phone home". That's enforced by routing, not just a firewall rule.

**Two threats, two axes:** Tiers protect against *attackers* (each layer reachable
only from the one above). AZs protect against *disasters* (any one data centre can
fail). 3 tiers × 3 AZs = 9 subnets.

**Supporting pieces:**
- **Internet Gateway** — the door between the public subnets and the internet.
- **NAT Gateway** — a *one-way* door: private pods can reach out (e.g. for updates),
  but the internet cannot reach in. (In dev I used one NAT to save cost; prod uses one
  per AZ for high availability — a single config flag.)
- **VPC Flow Logs** — a record of every network connection, for security
  investigation. A government compliance expectation.
- **VPC Endpoints** — private "corridors" to AWS services (like S3) so traffic never
  crosses the public internet. The free S3 gateway endpoint also reduces NAT costs.

---

## 2.6 Containers, Docker & ECR — packaging and storing the app

**What a container is:** Your application packed in a box with everything it needs to
run — code, runtime, libraries, config. The same box runs identically on a laptop and
in AWS. It kills "works on my machine".

**The Dockerfile choices (each is an interview point):**
- **Multi-stage build** — a "builder" stage installs dependencies; a fresh "runtime"
  stage copies only what's needed. Build tools never reach production → smaller, safer
  image.
- **Alpine base image** — a tiny Linux (~5MB) → less to download, smaller attack
  surface.
- **Non-root user (numeric UID)** — if someone breaks out of the app, they aren't root
  inside the container. (A real lesson: Kubernetes' `runAsNonRoot` needs a *numeric*
  UID, not a username, so it can verify non-root before starting the container.)
- **HEALTHCHECK** — the container can report whether it's alive.

**What ECR is:** Elastic Container Registry — a private, managed store ("warehouse")
for container images. EKS pulls images from here.

**Its role & key settings:**
- **Immutable tags** — once an image is tagged (I use the **git commit SHA**), that tag
  can never point to different content. What you tested is exactly what you deploy.
  This is why a code change *forces* a new commit and a new image — full traceability.
- **Scan on push** — images are checked for known vulnerabilities (CVEs) as they
  arrive. (A lesson learned: the default buildx attestation manifest isn't scanned by
  *basic* scanning — so "scan enabled" doesn't mean "scan ran". Verify the findings
  exist, or use Inspector enhanced scanning.)
- **Lifecycle policy** — keep the newest N images, expire the rest, so storage doesn't
  grow forever.

---

## 2.7 Amazon EKS & Kubernetes — running the containers

**What Kubernetes is:** An automated operations manager for containers. You declare
"run 2 copies of this image, here's how to health-check them, here are their limits",
and Kubernetes makes it true — and *keeps* it true. A pod crashes → replaced in
seconds. A node dies → its pods are rescheduled elsewhere.

**What EKS adds:** EKS is **managed Kubernetes** — AWS runs the hard part (the control
plane / "brain") so you don't have to. You bring the worker machines.

**Vocabulary (in building terms):**
- **Pod** — one running container (a member of staff at a desk).
- **Node** — a worker machine (EC2 server) that pods run on.
- **Control plane** — Kubernetes' brain; AWS-managed in EKS.
- **Deployment** — your declaration of "run N replicas of this image", and the thing
  that performs **rolling updates** (start new healthy pods, *then* remove old ones →
  zero downtime).
- **Service (ClusterIP)** — one stable internal address for a set of pods (pods come
  and go with changing IPs; the Service is the steady front door). Routing is by
  **labels**, not IPs.
- **Labels & selectors** — the universal glue: a Deployment stamps pods with a label,
  a Service routes to that label. No hard-coded addresses anywhere.

**The pod settings I used and why:**
- **Liveness probe** — "is it alive?" Fail → restart the pod.
- **Readiness probe** — "ready for traffic?" Fail → remove from the Service (no
  restart). Protects users during startup or brief overload.
- **resources.requests/limits** — requests are guaranteed (used for scheduling); limits
  are the hard ceiling (exceed memory → the pod is killed). One service can't starve
  the others.
- **securityContext** — non-root, no privilege escalation, read-only root filesystem,
  all Linux capabilities dropped. Defence in depth at the container level.

**Cost choice:** **Spot** worker nodes — AWS spare capacity at ~70% off, which AWS can
reclaim with 2 minutes' notice; Kubernetes simply reschedules the pods. Ideal for dev.

---

## 2.8 IRSA — a unique IAM identity per pod

**What it is:** IAM Roles for Service Accounts. It lets each Kubernetes pod assume its
own IAM role instead of borrowing the worker node's permissions.

**The problem it solves:** Without it, every pod on a node shares the node's IAM
permissions — so a compromised pod gets everything. IRSA gives each pod *only* what it
needs.

**How it works — the two-half handshake:**
1. **IAM side (Terraform):** an IAM role whose **trust policy** says "only the
   Kubernetes service account `<namespace>/<name>` on *this* cluster may assume me",
   verified through the cluster's **OIDC provider** (an identity provider AWS trusts).
2. **Kubernetes side:** the service account is **annotated** with that role's ARN.
When the pod calls AWS, it presents its service-account token; AWS verifies it via OIDC
and issues temporary credentials for that role. **No static keys, ever.**

**Where I used it twice:**
- The **AWS Load Balancer Controller** assumed a role to create the ALB.
- **user-service** assumed a role scoped to read exactly **one** Secrets Manager secret
  (the database password) — nothing else.

**Interview soundbite:** *"Each pod has its own least-privilege IAM identity via IRSA —
the role's trust policy names the exact service account, so a compromised pod can't
assume another's role, and there are no long-lived keys anywhere in the cluster."*

---

## 2.9 ALB & the Load Balancer Controller — the public front door

**What an ALB is:** Application Load Balancer — the single public entry point. It does
three jobs: **routes** requests to the right service by path, **balances** load across
healthy pods, and **health-checks** each pod (stops sending traffic to unhealthy ones).
Visitors only ever meet the ALB; they never learn where the pods are.

**What the Load Balancer Controller is:** A Kubernetes component (installed via
**Helm**) that *watches* for Ingress objects and, when it sees one, calls the AWS API
(using its IRSA role) to build a real ALB matching your declaration.

**What an Ingress is:** A Kubernetes object that **declares intent** — "I want a public
HTTP route to this service, health-checked at /health". You describe the route; the
controller turns it into infrastructure. This is the **operator pattern**: declare
desired state, a controller reconciles reality to match.

**Helm, briefly:** A package manager for Kubernetes (like apt/npm). I use **plain
manifests for my own apps** (the team owns and reviews them) and **Helm for
third-party platform components** like the controller (versioned, repeatable installs).

**An honesty point for the interview:** my dev ALB was HTTP-only and open to the world.
In production I'd add an **ACM** TLS certificate (HTTPS), a **WAF** with OWASP rules
and rate limiting, and UK geo-restriction.

---

## 2.10 RDS PostgreSQL & Secrets Manager — durable state, safe secrets

**What RDS is:** Relational Database Service — a managed database (PostgreSQL here).
AWS handles backups, patching, and failover, so I don't run a database server by hand.

**Its role & settings:**
- Lives in the **data subnets**, with a **security group** allowing port 5432 **only**
  from the EKS cluster's security group — not the internet, not the rest of the VPC.
- **Encrypted at rest** (KMS).
- **Multi-AZ** is a one-line flag: off in dev (cost), on in prod (a synchronised
  standby in another AZ fails over in ~1 minute, automatically).
- **Automated backups** with retention.

**What Secrets Manager is:** A secure, encrypted store for secrets (passwords, keys),
with access logging and automatic rotation.

**The elegant bit — `manage_master_user_password`:** RDS itself **creates and rotates**
the master password directly in Secrets Manager. The password therefore **never
appears in my Terraform code or state**, and no human ever sees it. The application
reads it at runtime via its **IRSA role**, which is scoped to that single secret ARN.

**Why not put the password in code or an environment variable?** Because code goes to
Git, and a secret in Git is a breach waiting to happen — one of the most common
real-world incidents. The best password is one no human has ever seen.

**Production enhancement:** the **External Secrets Operator** can sync Secrets Manager
into native Kubernetes secrets automatically — the fully Kubernetes-native pattern.

---

## 2.11 How it all connects — the end-to-end request path

```
1. A citizen's browser calls the public URL.
2. DNS resolves to the ALB in the PUBLIC subnets.
3. The ALB health-checks and forwards to a healthy user-service POD in a
   PRIVATE subnet (routing directly to the pod's IP).
4. The pod (running as non-root, read-only filesystem) handles the request.
5. On startup the pod used its IRSA role to read the DB password from
   Secrets Manager, then connected to RDS in the DATA subnets over port 5432
   (allowed only from the cluster's security group).
6. RDS returns the data; the pod responds; the ALB returns it to the citizen.

Cross-cutting: VPC Flow Logs record the network activity, CloudTrail records
every AWS API call, SCPs cap what the account can do, and SSO means no human
holds a long-lived key anywhere in the chain.
```

---

## 2.12 Operating it — the lifecycle & lessons

**The day-to-day Terraform loop:**
`write code → terraform plan (the dry run — always read it) → terraform apply →
terraform destroy`. In a pipeline, the plan is saved and reviewed, and apply runs only
the approved plan.

**Cost management:** I tore down compute (EKS, RDS, NAT, ALB) at the end of each
session and rebuilt with one command — keeping spend low *and* continuously proving the
IaC and disaster-recovery story.

**Teardown order matters (a real lesson):** the ALB was created by the *controller*,
not Terraform, so I deleted the Ingress first (letting the controller remove its own
ALB) **before** destroying the cluster — otherwise the ALB orphans, keeps billing, and
its network interfaces block the VPC from deleting.

**"Verify, don't trust" (the theme that recurred):**
- A "successful" destroy returned exit code 0 but had actually failed (needed
  `terraform init` after new modules were added) — the resources were still running and
  billing. I only caught it by checking the AWS API directly.
- "Scan on push enabled" didn't mean images were actually scanned (buildx attestation
  manifest). Enabled ≠ executed.
- A deploy that *looked* applied had pods erroring — `kubectl describe` showed the real
  reason. **Always read the actual state, never assume.**

---

# PART 3 — RAPID-FIRE Q&A (likely follow-ups)

**Q: Why EKS and not ECS?**
A: EKS is the industry-standard Kubernetes, with portable skills, fine-grained pod IAM
via IRSA, and a rich ecosystem (network policies, GitOps, operators) — which is how
large departments run containers at scale. ECS Fargate is simpler with less overhead
and is the right call for smaller/straightforward workloads. Being able to justify the
trade-off matters more than the choice itself.

**Q: How do you keep dev and prod consistent?**
A: Identical Terraform modules; only the input values differ per environment. Prod
flips a few flags (Multi-AZ database, one NAT per AZ, private API endpoint). Same
architecture by construction.

**Q: How is least privilege enforced?**
A: SCPs cap the account; IAM roles grant minimal permissions; IRSA gives each pod its
own scoped role; the user-service role can read exactly one secret ARN; no static keys
exist anywhere — access is temporary via SSO and OIDC.

**Q: What happens if a pod or a whole AZ dies?**
A: A pod crash → the Deployment restarts it in seconds. A node/AZ failure → pods
reschedule onto healthy nodes in other AZs; the ALB stops routing to unhealthy targets.
In prod, RDS Multi-AZ fails over to its standby automatically.

**Q: How do you do zero-downtime deployments?**
A: Kubernetes rolling updates — new healthy pods come up and pass readiness checks
*before* old pods are terminated. I watched this happen live during the build.

**Q: Where are your secrets?**
A: In Secrets Manager, created and rotated by RDS, read at runtime via IRSA — never in
code, state, or environment variables baked into images.

**Q: How would you onboard a new team onto the platform?**
A: Vend them an account via Control Tower Account Factory (guardrails auto-applied),
give them the Terraform modules and a starter service template, grant SSO access with a
scoped permission set, and point them at the CI/CD pipeline. Days, not weeks.

---

## One-paragraph summary to memorise

> "I built GovPlatform end to end as Infrastructure as Code: a Control Tower
> multi-account foundation with SCP guardrails and SSO-only access; a 3-tier,
> 3-AZ VPC; an EKS container platform with per-pod IAM via IRSA; a containerised
> service built, scanned, immutably tagged, and pushed to ECR, then deployed with
> health checks and a hardened security context; a public path through an
> ALB provisioned by the Load Balancer Controller; and a PostgreSQL RDS database in an
> isolated data tier with its password created and rotated by Secrets Manager and read
> via a least-privilege IRSA role. It deploys from commit to running in under 20
> minutes, rebuilds from an empty account with one command, and is secure by design."
