# GovPlatform UK — Full AWS DevOps Project

> A production-grade, secure AWS platform for government-style microservices.
> Built to develop and demonstrate every skill required for a Senior AWS DevOps Engineer role.

---

## Who This Project Is For

This project is for you if:
- You are preparing for a Senior AWS DevOps Engineer interview (specifically DWP or similar UK Government roles)
- You want to build something real, not just follow a tutorial
- You want to understand **why** every decision was made, not just **what** was built

Every section of this README explains not just what to do, but **why it matters**, **what you learn**, and **what to say about it in an interview**.

---

## Table of Contents

1. [What We Are Building](#what-we-are-building)
2. [The Big Picture — Architecture](#the-big-picture--architecture)
3. [Project Structure Explained](#project-structure-explained)
4. [Phase 0 — AWS Control Tower and Landing Zone](#phase-0--aws-control-tower-and-landing-zone)
5. [Phase 1 — Core Infrastructure with Terraform](#phase-1--core-infrastructure-with-terraform)
6. [Phase 2 — Build Your First Service](#phase-2--build-your-first-service)
7. [Phase 3 — CI/CD Pipeline](#phase-3--cicd-pipeline)
8. [Phase 4 — Security Hardening](#phase-4--security-hardening)
9. [Phase 5 — Monitoring and Observability](#phase-5--monitoring-and-observability)
10. [Phase 6 — Remaining Services](#phase-6--remaining-services)
11. [Key Design Decisions Explained](#key-design-decisions-explained)
12. [Interview Preparation Guide](#interview-preparation-guide)
13. [Cost Guide](#cost-guide)

---

## What We Are Building

### The Platform, Not the Applications

This is the most important thing to understand before you write a single line of code.

**We are not building four government applications.**
**We are building the platform that those applications run on.**

Think of it like this: a hotel does not just build rooms — it builds the entire building including plumbing, electricity, fire safety systems, elevators, and security. The rooms (the services) are only useful because the building (the platform) exists.

The four services we deploy are deliberately minimal. They exist to prove that the platform works. In a real job, product teams would own those services. A DevOps platform team owns the ground they run on.

### What the Platform Provides

Every service that deploys onto GovPlatform UK automatically gets:

| Capability | How We Deliver It |
|---|---|
| Automated deployment | GitHub Actions + CodePipeline |
| Container orchestration | AWS EKS (Kubernetes) |
| Zero-downtime deploys | Rolling updates (dev) + Canary (prod) |
| Auto-scaling | Kubernetes HPA + Cluster Autoscaler |
| Secrets management | AWS Secrets Manager + External Secrets Operator |
| Structured logging | Fluent Bit → CloudWatch Logs |
| Distributed tracing | AWS X-Ray |
| Metrics and alerting | CloudWatch + Managed Grafana |
| Vulnerability scanning | Trivy + Inspector v2 + Semgrep |
| WAF protection | AWS WAF with OWASP rules |
| Compliance monitoring | AWS Config + Security Hub + GuardDuty |
| Encryption everywhere | KMS for all data at rest and in transit |

### The Four Tenant Services (Proving the Platform Works)

```
1. User Identity Service      → stateful service with a database
2. Claim Processing Service   → event-driven with SQS and DynamoDB
3. Case Management Service    → internal-only (no public internet access)
4. Document Upload Service    → S3 pre-signed URLs + virus scanning
```

Each service demonstrates a different platform capability. Together they cover every pattern a real DWP developer team would need.

---

## The Big Picture — Architecture

Read this diagram carefully. It shows how everything connects.

```
┌──────────────────────────────────────────────────────────────────┐
│                    AWS ORGANISATIONS                              │
│                                                                   │
│  ┌─────────────────┐    ┌─────────────────────────────────────┐  │
│  │  Management     │    │  GovPlatform OU                     │  │
│  │  Account        │    │                                     │  │
│  │  (your existing │    │  ┌──────────────────────────────┐   │  │
│  │   account)      │    │  │  govplatform-dev account     │   │  │
│  │                 │───►│  │                              │   │  │
│  │  Control Tower  │    │  │  Everything below lives here │   │  │
│  │  Landing Zone   │    │  └──────────────────────────────┘   │  │
│  │  SCPs applied   │    └─────────────────────────────────────┘  │
│  └─────────────────┘                                             │
└──────────────────────────────────────────────────────────────────┘

                    Inside govplatform-dev:

  Developer                                         AWS
  ─────────                                         ───
  Writes code
      │
      ▼
  GitHub (source of truth)
      │
      ├──► GitHub Actions (fast feedback — tests, scans, build)
      │         │
      │         ▼
      │     AWS ECR (stores Docker images, tagged with git SHA)
      │         │
      └──► AWS CodePipeline (deployment governance + audit trail)
                │
                ├── Stage: Deploy Dev → EKS (rolling update)
                ├── Stage: Manual Approval (email via SNS)
                └── Stage: Deploy Prod → EKS (canary 10% → 100%)

  EKS Cluster (Kubernetes)
  ┌────────────────────────────────────────────────┐
  │  user-service pods (×2)                        │
  │  claim-service pods (×2)        Auto-scales    │
  │  case-service pods (×2)         up to ×10      │
  │  document-service pods (×2)                    │
  │                                                │
  │  Platform add-ons:                             │
  │  - Fluent Bit (log shipping)                   │
  │  - AWS Load Balancer Controller (creates ALBs) │
  │  - External Secrets Operator (syncs secrets)   │
  │  - Cluster Autoscaler (adds/removes EC2 nodes) │
  └────────────────────────────────────────────────┘
         │                        │
         ▼                        ▼
  Public-facing services    Internal-only services
  (ALB + WAF)               (ClusterIP only)
  user-service              case-service
  claim-service
  document-service

  Data Layer:
  RDS PostgreSQL (Multi-AZ) — user and claim data
  DynamoDB — claim status tracking (fast reads)
  S3 — document storage (encrypted)
  ElastiCache Redis — session caching

  Security Plane (runs continuously):
  GuardDuty → Security Hub → SNS → email alerts
  AWS Config Rules → auto-remediation
  CloudTrail → every API call logged forever
  WAF → OWASP rules + rate limiting + UK-only geo restriction
  Inspector v2 → scans ECR images for CVEs on every push

  Observability Plane:
  CloudWatch → metrics, alarms, dashboards
  CloudWatch Logs → all container logs centralised
  X-Ray → distributed traces (what's slow and why)
  Synthetics Canary → health checks every 5 minutes
  Managed Grafana → visual dashboards
```

### Why This Architecture?

**Junior engineer question:** "Why is it this complicated?"

**Honest answer:** Each layer solves a specific problem that you will encounter in a real job.

- **Multiple accounts (Control Tower):** Prevents a mistake in the dev environment from affecting production. Also required for government compliance.
- **Separate VPC subnets for data:** If someone compromises the application layer, the database is still behind an additional network boundary.
- **Two CI/CD tools (GitHub Actions + CodePipeline):** GitHub Actions is for developer speed (feedback in 3 minutes). CodePipeline is for deployment governance (audit trail, approval gates — required in regulated environments).
- **EKS instead of just EC2:** Kubernetes handles health checks, restarts, scaling, and rolling deployments automatically. You write a manifest once; Kubernetes keeps your service running.

---

## Project Structure Explained

```
FullAWSDevOpsProject/
│
├── README.md                    ← You are here
│
├── services/                    ← The four tenant microservices
│   ├── user-service/            ← Start here — simplest service
│   ├── claim-service/
│   ├── case-service/
│   └── document-service/
│
├── infrastructure/
│   ├── terraform/               ← Defines all AWS infrastructure as code
│   │   ├── main.tf              ← Ties all modules together
│   │   ├── variables.tf         ← All input parameters
│   │   ├── environments/
│   │   │   ├── dev.tfvars       ← Dev environment values
│   │   │   └── prod.tfvars      ← Prod environment values
│   │   ├── bootstrap/           ← One-time setup (S3 state bucket)
│   │   └── modules/
│   │       ├── vpc/             ← Network: subnets, NAT, flow logs
│   │       ├── eks/             ← EKS cluster, node groups, IRSA
│   │       ├── ecr/             ← Container registries
│   │       ├── rds/             ← PostgreSQL database
│   │       ├── alb/             ← Application Load Balancer
│   │       ├── waf/             ← Web Application Firewall
│   │       └── monitoring/      ← CloudWatch alarms, dashboards
│   │
│   ├── cdk/                     ← AWS CDK (TypeScript) for pipelines
│   │   ├── bin/app.ts           ← CDK entry point
│   │   └── lib/pipeline-stack.ts
│   │
│   └── cloudformation/          ← CFN for services that need it
│
├── cicd/
│   ├── buildspec/               ← CodeBuild instructions
│   │   ├── buildspec-build.yml       ← Build + test
│   │   ├── buildspec-security.yml    ← Security scanning
│   │   └── buildspec-deploy-dev.yml  ← Deploy to dev
│   └── pipeline/
│       └── pipeline.yml         ← CodePipeline definition
│
├── k8s/                         ← Kubernetes manifests
│   ├── user-service/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   ├── hpa.yaml             ← Auto-scaling rules
│   │   ├── pdb.yaml             ← Prevents all pods going down at once
│   │   └── external-secret.yaml ← Syncs from Secrets Manager
│   └── [other-services]/
│
├── security/
│   ├── iam/                     ← IAM roles, policies, permission boundaries
│   ├── scp/                     ← Org-level guardrails
│   └── config-rules/            ← Compliance rules
│
├── monitoring/
│   ├── cloudwatch/              ← Dashboards and log queries
│   └── xray/                    ← Tracing configuration
│
├── scripts/
│   ├── linux/                   ← Bash automation scripts
│   └── windows/                 ← PowerShell scripts
│
├── tests/
│   ├── unit/                    ← Fast unit tests (no AWS)
│   └── integration/             ← Tests against running service
│
└── docs/
    ├── product-story.md         ← What we're building and why
    ├── project-plan.md          ← Phase-by-phase build guide
    ├── combined-architecture.md ← Why we made key decisions
    ├── deployment-guide.md      ← Step-by-step deployment instructions
    └── runbook.md               ← What to do when things break
```

**Lesson for junior engineers:** A well-organised repository is itself a form of documentation. When a new engineer joins the team, they should be able to navigate to any file by reading the directory names alone. If you find yourself putting files in `misc/` or `stuff/`, that is a sign to reorganise.

---

## Phase 0 — AWS Control Tower and Landing Zone

> **What you learn:** Account vending, Landing Zone design, SCPs, IAM Identity Center
> **Why it matters for DWP:** Enterprise organisations like DWP manage hundreds of AWS accounts. Control Tower is how they ensure every account meets security standards from day one.

### What Is Control Tower and Why Does It Exist?

**The problem it solves:**

Without Control Tower, imagine you have 50 development teams. Each team needs an AWS account. You create 50 accounts manually. Six months later:
- Account 12 has GuardDuty disabled because someone turned it off to save cost
- Account 27 has an S3 bucket accidentally made public
- Account 35 still uses root account credentials
- Account 49 is deploying into `us-east-1` (American data centres) instead of UK ones

You will never know unless you manually check all 50 accounts.

**With Control Tower:**

Every new account is created from a template (Account Factory). Security controls are enforced by Service Control Policies (SCPs) at the Organisation level — even the account's own administrator cannot turn them off. This is called a "guardrail."

**Interview explanation:** *"Control Tower gives us a consistent baseline across all accounts. SCPs act as a ceiling — even if an IAM admin inside a child account tries to disable GuardDuty, the SCP at the OU level blocks the action. This is defence in depth applied at the account level."*

### What Is an Organisational Unit (OU)?

Think of OUs like folders in a filing cabinet. Policies applied to a folder apply to everything inside it.

```
Root
├── Management (your existing account)
├── Security OU (created by Control Tower)
│   ├── Log Archive account
│   └── Audit account
└── GovPlatform OU  ← we create this
    ├── govplatform-dev account  ← our practice account
    └── govplatform-prod account (future)
```

SCPs applied to `GovPlatform OU` apply to both accounts inside it. Change the SCP once — it applies everywhere in the OU.

### What Are SCPs and Why Are They Different from IAM Policies?

| IAM Policy | Service Control Policy (SCP) |
|---|---|
| Applied to a specific user, role, or group | Applied to an entire AWS account or OU |
| Grants permissions | Sets a maximum permission boundary |
| Can be overridden by a more permissive policy | Cannot be overridden — it is a hard ceiling |
| You manage it per-user | Managed centrally from the management account |

**Real example:** Imagine a developer accidentally creates an IAM policy with `Effect: Allow, Action: "*"`. Without an SCP, that developer now has root-level access. With an SCP that says `"Deny: cloudtrail:StopLogging"`, they still cannot stop CloudTrail even with full IAM permissions. The SCP wins.

### Step-by-Step: Control Tower Setup

See the full steps in [`docs/deployment-guide.md`](docs/deployment-guide.md) — Phase 0.

**After completing Phase 0, you will have:**
- A dedicated `govplatform-dev` AWS account
- GuardDuty, Config, and CloudTrail pre-enabled
- SCPs preventing root usage and region restriction
- SSO access — no IAM users needed

---

## Phase 1 — Core Infrastructure with Terraform

> **What you learn:** Terraform modules, remote state, VPC design, EKS, ECR, IAM
> **Why it matters for DWP:** "Demonstrable knowledge of writing and maintaining Infrastructure as Code" is an essential criterion.

### Why Terraform and Not the AWS Console?

This is the most fundamental DevOps principle and you must be able to explain it clearly.

**The problem with clicking in the console:**

Imagine you build your entire platform by clicking through the AWS console. Six months later:
- Your colleague needs to build an identical environment for testing. They click through the same screens, making 3 slightly different choices. Environments drift.
- You need to add a new subnet. You add it manually. Nobody else knows.
- A developer accidentally deletes the VPC. You spend 2 days rebuilding it from memory.
- A security audit asks "what is the exact configuration of your production environment?" You cannot answer precisely.

**With Terraform (Infrastructure as Code):**

Your infrastructure is a text file checked into Git. To recreate the entire platform from scratch: `terraform apply`. Takes 20 minutes. Identical every time. Every change is a Git commit — auditable, reversible, reviewable.

**Interview explanation:** *"IaC means our infrastructure has the same quality controls as our application code — peer review, version history, automated testing with Checkov, and the ability to rebuild from zero if needed. The Terraform state file is the authoritative record of what exists in AWS."*

### Understanding Terraform Remote State

When Terraform runs, it needs to track what it has already created. It stores this in a "state file."

**Why the state file cannot be local:**

If your state file is on your laptop:
- Your colleague runs `terraform apply` from their laptop — no state file — Terraform thinks nothing exists — tries to create everything again — conflict
- Your laptop dies — state file gone — Terraform no longer knows what it manages

**Remote state solution:** Store the state file in S3 (encrypted, versioned). Use DynamoDB as a "lock" — only one person can run Terraform at a time.

```
Your laptop                S3 Bucket (state)       DynamoDB (lock)
     │                          │                        │
     │── terraform plan ────►   │                        │
     │                          │                        │
     │── terraform apply ──►    │── acquire lock ──────► │
     │                          │                        │ ← locked
     │                          │                        │
     │── creates resources      │                        │
     │                          │                        │
     │── write new state ──►    │── release lock ──────► │
     │                          │                        │ ← unlocked
```

**The bootstrap problem:** You need an S3 bucket to store state, but Terraform manages S3 buckets. You must create the first S3 bucket manually (or with a bootstrap script) before Terraform can manage itself. This is explained fully in `infrastructure/terraform/bootstrap/`.

### The VPC Design — Three Tiers Explained

Most tutorials show a 2-tier VPC (public + private). We use 3 tiers. Here is why.

```
Internet
    │
    ▼
┌─────────────────────────────────┐
│  PUBLIC SUBNETS (10.0.1.0/24)   │ ← Only ALB lives here
│  - Application Load Balancer    │   Citizens hit this
│  - NAT Gateway                  │
└──────────────┬──────────────────┘
               │ (ALB only forwards HTTPS to private layer)
               ▼
┌─────────────────────────────────┐
│  PRIVATE SUBNETS (10.0.10.0/24) │ ← Application code lives here
│  - EKS worker nodes             │   No public IP addresses
│  - Lambda functions             │
└──────────────┬──────────────────┘
               │ (application code only connects to data layer)
               ▼
┌─────────────────────────────────┐
│  DATA SUBNETS (10.0.20.0/24)    │ ← Databases live here
│  - RDS PostgreSQL               │   No route to internet at all
│  - ElastiCache Redis            │
└─────────────────────────────────┘
```

**Why a separate data subnet?**

If an attacker somehow compromises a pod in the private subnet, they still face a second barrier to reach the database: the data subnet NACL and security group rules. This is called "defence in depth" — multiple independent layers of protection. If one fails, the next layer still holds.

**Without data subnets:** A compromised application container can directly attempt database connections.
**With data subnets:** A compromised container can attempt connections, but the NACL blocks all traffic from non-application IPs. The attacker needs to compromise two layers, not one.

### Understanding IRSA — IAM Roles for Service Accounts

This is one of the most important EKS concepts for a Senior engineer to explain clearly.

**The old way (bad):** Give the EC2 node an IAM role. All pods on that node share the same role. If Service A needs DynamoDB access, Service B (also on that node) also gets DynamoDB access.

**IRSA (correct):** Each Kubernetes service account gets its own IAM role. Pod A can only assume Role A. Pod B can only assume Role B. Even if they run on the same EC2 node.

```
Pod A (user-service)                    Pod B (claim-service)
ServiceAccount: user-service-sa         ServiceAccount: claim-service-sa
       │                                        │
       ▼                                        ▼
IAM Role: user-service-role             IAM Role: claim-service-role
Permissions:                            Permissions:
- DynamoDB:GetItem on users-table       - DynamoDB:PutItem on claims-table
- SecretsManager on user-service/*      - SQS:SendMessage on claims-queue
                                        - S3:PutObject on claims-documents/*
```

Pod A cannot access the claims table. Pod B cannot access user secrets. If either pod is compromised, the blast radius is limited to that service's permissions only.

**Interview explanation:** *"IRSA implements least-privilege at the pod level. Each service account is annotated with an IAM role ARN. When a pod assumes the role, AWS validates the Kubernetes service account token via the OIDC provider. No static credentials are stored anywhere."*

---

## Phase 2 — Build Your First Service

> **What you learn:** Dockerising an application, Kubernetes manifests, health checks, secrets injection
> **The rule:** If it doesn't work locally first, don't deploy it to AWS

### The User Service

We start with this service because it is the simplest: one database, two endpoints, one health check.

```
POST /users         → create a user
GET  /users/:id     → retrieve a user
GET  /health        → returns "healthy" + checks DB connection
GET  /api-docs      → auto-generated OpenAPI documentation
```

**Why include database connectivity in the health check?**

A health check that only returns `200 OK` without checking the database is dangerous. The service appears healthy to Kubernetes, but every user request that needs the database fails. Kubernetes never restarts it. Users see errors.

A correct health check queries the database: `SELECT 1`. If that fails, the health endpoint returns `503` and Kubernetes restarts the pod. Users see a brief restart instead of sustained errors.

### Understanding the Multi-Stage Dockerfile

```dockerfile
# ---- Stage 1: Builder ----
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
# Only install production dependencies — dev dependencies not needed in runtime image

# ---- Stage 2: Runtime ----
FROM node:20-alpine AS runtime
# Why start fresh? The builder stage has npm, build tools, caches — not needed at runtime
# Starting fresh keeps the image small (attack surface) and fast (less to pull)

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
# Why: Running as root inside a container is dangerous.
# If the container is compromised, the attacker has root.
# Non-root user limits what an attacker can do.

WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
# Only copy the node_modules from builder — not the npm itself
COPY src ./src

USER appuser
# Switch to non-root user before running the application

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://localhost:3000/health || exit 1
# Kubernetes reads this — if it fails 3 times, the container is restarted

CMD ["node", "src/index.js"]
```

**Why multi-stage?** Compare image sizes:
- Single stage (with all build tools): ~400MB
- Multi-stage (runtime only): ~80MB

A smaller image means faster deployments, less ECR storage cost, and a smaller attack surface.

### Understanding Kubernetes Manifests

Each service has these Kubernetes files:

**deployment.yaml** — defines the pods
```yaml
spec:
  replicas: 2               # Always run 2 copies
  strategy:
    rollingUpdate:
      maxUnavailable: 1     # At most 1 pod can be down during deployment
      maxSurge: 1           # Can temporarily have 3 pods during rollout
```

**Why 2 replicas minimum?** If you run 1 replica and Kubernetes needs to restart it (upgrade, health check failure, node drain), you have 0 running pods for a few seconds. With 2, one is always available while the other restarts.

**hpa.yaml** — auto-scaling
```yaml
spec:
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

**Lesson:** When CPU across all pods averages 70%, Kubernetes adds more pods. This handles traffic spikes automatically. Without this, your service falls over under load. With it, it scales elastically.

**pdb.yaml** — PodDisruptionBudget
```yaml
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: user-service
```

**Lesson:** This is a safety guarantee. When a node is drained (for maintenance or an upgrade), Kubernetes will not evict ALL pods of this service at once. At least 1 will always remain running. Without this, a cluster upgrade causes downtime.

**external-secret.yaml** — connects Kubernetes to Secrets Manager
```yaml
spec:
  refreshInterval: 1h
  data:
    - secretKey: DB_URL
      remoteRef:
        key: govplatform/dev/user-service/db-url
```

**Lesson:** This is the bridge between AWS Secrets Manager and a Kubernetes Secret. The External Secrets Operator runs in the cluster and syncs the value every hour. If someone rotates the database password in Secrets Manager, the Kubernetes Secret is automatically updated within 1 hour — without a redeployment.

---

## Phase 3 — CI/CD Pipeline

> **What you learn:** GitHub Actions, CodePipeline, CodeBuild, ECR, rolling deployments, approval gates
> **Why it matters for DWP:** "Demonstrable knowledge of implementing and maintaining CI/CD pipelines" is an essential criterion

### Why We Use Both GitHub Actions AND CodePipeline

This is a question you will be asked. Here is the complete answer.

**GitHub Actions (runs on every commit and PR)**
- Purpose: Fast feedback to developers
- Triggers: Every `git push`, every pull request
- Jobs run in parallel — lint, test, scan, build all at once
- If any job fails, the developer knows within 3 minutes
- Runs in GitHub's infrastructure — no AWS cost

**CodePipeline (runs on merge to main)**
- Purpose: Deployment governance and audit trail
- Every deployment has an approval record
- Every deployment is logged in CloudTrail
- Integrates natively with CodeDeploy for blue/green
- Manual approval gate before production
- Required in regulated environments (government)

**The combined flow:**
```
Developer pushes commit
    │
    ▼
GitHub Actions runs (3–4 minutes)
├── Lint + unit tests
├── Security scan (Trivy, Semgrep, detect-secrets)
├── Build Docker image
└── Push to ECR (tagged: git-SHA)
    │
    │ (only on merge to main)
    ▼
CodePipeline runs (5–8 minutes)
├── Source: detect new ECR image
├── Build: update K8s manifests with new image tag
├── Deploy Dev: kubectl apply → smoke tests
├── Approval: email to team lead
└── Deploy Prod: canary 10% → alarms OK → 100%
```

**Interview answer:** *"GitHub Actions gives developers fast feedback — they know within minutes if their PR breaks anything. CodePipeline provides the governance layer — every production deployment has an approval record, a build log, and a deployment audit trail. In a regulated environment like DWP, that audit trail is not optional."*

### Understanding the Buildspec Files

A `buildspec.yml` is the instruction manual for CodeBuild. Think of it as a recipe.

```yaml
version: 0.2

phases:
  install:                    # Set up the environment
    commands:
      - npm ci                # Install dependencies (ci = clean install, faster)

  pre_build:                  # Run before building
    commands:
      - npm run lint          # Check code style
      - npm audit             # Check for known vulnerabilities in dependencies

  build:                      # The main work
    commands:
      - npm test              # Run unit tests
      - docker build ...      # Build the container image
      - docker push ...       # Push to ECR

  post_build:                 # Cleanup and artifacts
    commands:
      - echo "Done"

artifacts:                    # Files to pass to the next pipeline stage
  files:
    - imagedefinitions.json
```

**Lesson:** The `pre_build` stage is where security checks go. This is called "shift-left security" — finding vulnerabilities at build time, not after deployment. A failed `npm audit` stops the pipeline before anything is deployed.

### Image Tagging Strategy — Why We Use Git SHA

```bash
# Never do this:
docker push my-app:latest

# Always do this:
IMAGE_TAG=$(git rev-parse --short HEAD)  # e.g. "a3b4c5d"
docker push my-app:$IMAGE_TAG
```

**Why not `:latest`?**

`:latest` is mutable — it points to a different image every time you push. If you deploy `:latest` in production and a developer pushes a broken build, your production deployment is `latest` too. You cannot tell which version is running.

With immutable SHA tags:
- `my-app:a3b4c5d` always refers to the exact commit `a3b4c5d`
- If production is running `a3b4c5d`, you know exactly which code is deployed
- You can roll back to any previous SHA instantly
- ECR is configured with `imageTagMutability: IMMUTABLE` — once pushed, a tag cannot be overwritten

---

## Phase 4 — Security Hardening

> **What you learn:** IAM permission boundaries, SCPs, AWS Config, GuardDuty, Security Hub, WAF, KMS
> **Why it matters for DWP:** Security is not optional in government. This is where Senior candidates differentiate themselves from Mid-level candidates.

### The Security Philosophy: Defence in Depth

Defence in depth means having multiple independent layers of security. Each layer assumes the previous one has been compromised.

```
Layer 1: Network — WAF, Security Groups, NACLs, private subnets
Layer 2: Identity — IAM least privilege, permission boundaries, IRSA
Layer 3: Data — KMS encryption at rest, TLS in transit, Secrets Manager
Layer 4: Detection — GuardDuty, CloudTrail, Config rules, Inspector
Layer 5: Response — SNS alerts, auto-remediation, runbooks
```

If layer 1 fails (network bypass), layer 2 stops the attacker.
If layer 2 fails (credential compromise), layer 3 means they still cannot read encrypted data.
If layer 3 fails, layer 4 detects the anomaly and layer 5 alerts the team.

### Understanding Permission Boundaries

This is an advanced IAM concept. Understand it and you will stand out.

**The problem:** Your CI/CD pipeline needs to create IAM roles (for new services). But if the pipeline can create ANY IAM role with ANY permissions, a compromised pipeline can create a role with `AdministratorAccess` and escalate privileges.

**Permission boundary solution:**

When the pipeline creates a new IAM role, it MUST attach a permission boundary. The permission boundary is a policy that says "this role can never have more than these permissions, regardless of what policies are attached to it."

```
Developer-created IAM Role
    │
    ├── Policies attached: ["AdministratorAccess"]   ← someone is being greedy
    │
    └── Permission Boundary: ["AllowOnlyDevOpsActions"]  ← this wins

Result: The role can only do what DevOpsActions allows,
        EVEN THOUGH AdministratorAccess is attached.
        The boundary is a hard ceiling.
```

**Interview explanation:** *"We attach permission boundaries to every role created by our pipelines. Even if a developer tries to grant their role more permissions than intended, the boundary prevents privilege escalation. It's a technical control that enforces least-privilege without relying on process alone."*

### Understanding AWS Config

AWS Config answers the question: "Is my AWS environment compliant with our security standards?"

It works like this:
1. You define a rule: "All S3 buckets must have encryption enabled"
2. Config continuously evaluates every S3 bucket against this rule
3. If a bucket is created without encryption, Config marks it `NON_COMPLIANT`
4. An auto-remediation action can automatically fix it

**The 15+ rules in this project cover:**
- S3: no public access, SSL only, encryption required
- IAM: MFA required, no root access keys, strong password policy
- Network: VPC flow logs enabled, no SSH open to internet
- Encryption: RDS encrypted, EBS encrypted
- Audit: CloudTrail enabled, CloudTrail encrypted

**Why Config instead of just checking manually?**
Config checks continuously. Manually checking happens quarterly at best. A misconfiguration introduced at 2pm on a Tuesday is detected within minutes. Manual review would find it in 3 months.

### Understanding GuardDuty

GuardDuty monitors your AWS account for suspicious activity using machine learning and threat intelligence feeds.

It analyses:
- CloudTrail events (API calls)
- VPC Flow Logs (network traffic)
- DNS logs (domain lookups)

**Examples of what it detects:**
- An EC2 instance is communicating with a known cryptocurrency mining pool
- IAM credentials are being used from an IP address in a country you never operate from
- A large amount of S3 data is being exfiltrated to an unusual location
- An EC2 port scan is being performed from inside your VPC (suggests a compromised instance)

**How we use it:**
```
GuardDuty finding
     │
     ▼
EventBridge rule (filter for HIGH/CRITICAL severity)
     │
     ▼
SNS Topic → email to security team
     │
     ▼
Lambda function → create Jira ticket automatically
```

High-severity findings trigger immediate alerts. The Lambda function creates a ticket automatically so nothing is missed.

### WAF — Web Application Firewall

The WAF sits in front of every public ALB. It inspects every HTTP request before it reaches your application.

```
Internet request
     │
     ▼
WAF WebACL
├── Rule 1: AWSManagedRulesCoreRuleSet (OWASP Top 10)
│   Blocks: SQL injection, XSS, path traversal, etc.
├── Rule 2: AWSManagedRulesSQLiRuleSet
│   Blocks: More SQL injection patterns
├── Rule 3: Rate limiting (2000 requests/5min per IP)
│   Blocks: Brute force and credential stuffing
└── Rule 4: Geo restriction (UK only)
    Blocks: All requests not from UK IP ranges
     │
     ▼
ALB → EKS → Your application
```

**Why UK-only geo restriction for DWP?**
Government services typically only need to serve UK residents. Restricting to UK IPs eliminates a large proportion of automated attack traffic (most botnets and scanners originate from data centres overseas). It also simplifies GDPR compliance — you know exactly where requests are coming from.

---

## Phase 5 — Monitoring and Observability

> **What you learn:** CloudWatch metrics/logs/alarms, X-Ray distributed tracing, Synthetics canaries, Grafana
> **Why it matters for DWP:** A Senior engineer is expected to diagnose production issues, not just deploy code

### The Three Pillars of Observability

Every production system needs three types of signals:

**1. Metrics (CloudWatch)**
Numbers that tell you the system is healthy or not.
- CPU utilisation: is the service overloaded?
- Error rate: are requests failing?
- P99 latency: are 99% of requests fast enough?
- Pod restart count: is something repeatedly crashing?

Metrics tell you THAT something is wrong.

**2. Logs (CloudWatch Logs via Fluent Bit)**
Text records of what happened.
- Application errors with stack traces
- Every HTTP request (method, path, status code, duration)
- Security events (authentication failures, authorisation denials)

Logs tell you WHAT happened.

**3. Traces (X-Ray)**
The journey of a single request through multiple services.
- User clicks "submit claim" on their browser
- Request hits ALB → claim-service → user-service (to validate user) → RDS → SQS
- X-Ray shows every step, how long each took, and where it failed

Traces tell you WHERE and WHY something is slow.

**Interview answer when asked about monitoring:** *"We use the three pillars of observability: metrics for health signals and alerting, logs for investigation and audit, and traces for diagnosing latency across service boundaries. CloudWatch alarms trigger within 60 seconds of a threshold breach. X-Ray service maps let us identify which downstream dependency is causing slowness without reading thousands of log lines."*

### Understanding Structured Logging

Compare these two log lines:

```
# Unstructured (bad)
2024-01-15 14:23:01 - Error processing request for user 12345

# Structured JSON (good)
{
  "timestamp": "2024-01-15T14:23:01.123Z",
  "level": "ERROR",
  "service": "user-service",
  "version": "1.2.3",
  "traceId": "1-65a5c2f5-abc123",
  "userId": "12345",
  "requestId": "req-xyz",
  "message": "Database query failed",
  "error": "connection timeout after 5000ms",
  "endpoint": "GET /users/12345",
  "duration_ms": 5001
}
```

With structured logs, you can write CloudWatch Logs Insights queries:
```sql
fields @timestamp, userId, error
| filter level = "ERROR" and service = "user-service"
| stats count(*) as errors by userId
| sort errors desc
| limit 10
```
This instantly shows you the 10 users experiencing the most errors. With unstructured text, you would be grepping through millions of lines.

**Lesson:** Structured logging is not about aesthetics. It is about enabling fast incident response. When something breaks at 2am, structured logs mean the difference between a 10-minute investigation and a 2-hour one.

### CloudWatch Synthetics Canaries

A Synthetics canary is a script that runs on a schedule and tests your service from outside your system.

```
Every 5 minutes:
Lambda function runs → hits https://your-alb-url/health → checks response is 200
    │
    ├── If 200 → record metric: "canary success"
    └── If not 200 → record metric: "canary failure"
              │
              └── After 2 consecutive failures → CloudWatch alarm → SNS → email
```

**Why this matters:** Your internal monitoring might show all pods healthy and all metrics normal. But if the ALB listener rule has a misconfiguration, external users still cannot reach your service. The canary tests from outside, simulating what a real user experiences.

---

## Phase 6 — Remaining Services

### Claim Processing Service — New Concepts

**SQS (Simple Queue Service) for decoupling:**

When a citizen submits a claim, we do not want the HTTP request to wait while we:
- Validate all the data
- Run fraud checks
- Send confirmation email
- Notify case workers

Instead: Accept the claim immediately, return `202 Accepted`, and put a message on an SQS queue. A separate worker process picks up the message and does the processing asynchronously.

```
Citizen submits claim
     │
     ▼ (immediate response)
claim-service: "Thank you, your claim is being processed"
     │
     │ (asynchronously)
     ▼
SQS Queue: claim-submissions
     │
     ▼
Worker pod: validate → fraud check → notify → update DynamoDB
```

**Why this is better:** The citizen gets an immediate response. The processing happens in the background. If processing fails, the message stays on the queue and can be retried. This is called "at-least-once delivery."

### Document Upload Service — Pre-Signed URLs

```
Traditional approach (wrong):
Browser → POST /upload → Your server → S3
        ↑ Every document goes through your server
        ↑ Large files consume server memory
        ↑ Server becomes a bottleneck

Pre-signed URL approach (correct):
Browser → GET /get-upload-url → Your server generates S3 pre-signed URL
        ← Returns: "https://s3.amazonaws.com/bucket/file?X-Amz-Signature=..."
Browser → PUT file directly to S3 (bypasses your server entirely)
        ← S3 returns 200
Browser → POST /confirm-upload → Your server records document metadata
```

**Benefits:** Your server only handles tiny metadata requests. S3 handles all the large file transfers. The pre-signed URL expires in 5 minutes — it cannot be reused after that.

**Lesson:** This pattern reduces server cost, improves upload speed for citizens (S3 is globally distributed), and removes your service as a single point of failure for document uploads.

---

## Key Design Decisions Explained

### Why Not Jenkins?

Jenkins is a valid CI/CD tool. But for this project we chose GitHub Actions + CodePipeline because:
1. GitHub Actions is SaaS — no infrastructure to maintain
2. CodePipeline is deeply integrated with AWS — native IAM, CloudTrail, CodeDeploy integration
3. DWP is likely migrating away from on-premise Jenkins toward managed services
4. Demonstrating multiple approaches proves breadth

**If asked in interview:** *"I chose GitHub Actions for the build stage because it requires zero infrastructure management and provides fast feedback on PRs. For the deployment stage, CodePipeline provides native AWS integration, an audit trail that satisfies governance requirements, and approval gates that enforce the four-eyes principle for production changes."*

### Why EKS Over Lambda for Services?

Lambda is excellent for event-driven, short-lived functions. We use it for:
- CodeDeploy lifecycle hooks
- Security findings processors
- Cost anomaly handlers

EKS is better for long-running services because:
- Services need persistent database connections (Lambda cold starts re-establish connections)
- Services need to handle sustained HTTP traffic (Lambda has concurrency limits)
- Kubernetes provides rich operational capabilities: rolling updates, health checks, resource limits, pod disruption budgets

### Why KMS Customer-Managed Keys?

AWS provides AWS-managed KMS keys for free. Why create customer-managed keys?

1. **Control:** You can rotate, disable, or delete the key yourself
2. **Auditability:** Every key usage is logged in CloudTrail with your key ARN
3. **Access control:** You decide which principals can use the key via the key policy
4. **Separation of duties:** The application role can decrypt; the pipeline role cannot (different keys)

For government data, using AWS-managed keys is usually acceptable. For Tier 2 or above data, customer-managed keys are required by NCSC guidance.

---

## Interview Preparation Guide

### The Technical Exercise (10 Minutes)

The job spec says you will have a 10-minute technical exercise. Based on similar DWP interviews, likely topics:

**Practice writing these from memory, timed at 10 minutes each:**

1. Write a CodeBuild buildspec for a Node.js app that runs tests, builds Docker, pushes to ECR
2. Write a Kubernetes Deployment manifest with resource limits, health checks, and a non-root user
3. Write a Terraform module for a VPC with public and private subnets
4. Design a CI/CD pipeline for a new microservice joining the platform (draw or write)
5. Review a CloudFormation template and identify 3 security issues

**How to practise:**
- Close this README
- Set a 10-minute timer
- Write from memory
- Compare with files in this repo
- Repeat weekly until you can do it without looking

### Mapping Your Experience to the Essential Criteria

**Criterion 1: IaC knowledge**
Point to: `infrastructure/terraform/` — VPC module, EKS module, monitoring module
Say: *"I built Terraform modules with input validation, remote state in S3 with DynamoDB locking, and KMS encryption. The modules are reused across dev and prod environments with different tfvars files. All IaC changes go through PR review before apply."*

**Criterion 2: Unix/Linux/Windows scripting**
Point to: `scripts/linux/deploy.sh`, `scripts/linux/rotate-secrets.sh`, `scripts/windows/Deploy-Application.ps1`
Say: *"I wrote Bash scripts using `set -euo pipefail` for safe error handling, AWS CLI for automation, and jq for JSON manipulation. The deploy script polls CodeDeploy status and fails fast with a clear error message. I also wrote equivalent PowerShell for Windows environments."*

**Criterion 3: CI/CD experience**
Point to: `.github/workflows/ci.yml`, `cicd/pipeline/pipeline.yml`, `cicd/buildspec/`
Say: *"I designed a dual pipeline: GitHub Actions for the developer feedback loop (lint, test, scan, build — 3 minutes) and CodePipeline for deployment governance (audit trail, approval gates, CodeDeploy Blue/Green). Security scanning runs in parallel with the build to avoid adding pipeline time."*

**Criterion 4: Guiding engineers**
Point to: This README, `docs/architecture.md`, `docs/runbook.md`
Say: *"I documented every architectural decision with explanations aimed at junior engineers — not just what was built but why each decision was made and what alternatives were considered. The runbook gives on-call engineers specific commands for each failure scenario."*

**Criterion 5: AWS cloud-based applications (Technical Breadth)**
Point to: The entire repository
Say: *"I built a four-service platform on EKS with full observability, automated security scanning in every pipeline, and defence-in-depth controls: WAF, GuardDuty, Config with auto-remediation, Inspector v2, and SCPs enforcing organisational guardrails. The platform is provisioned from code — the entire environment can be rebuilt from scratch in under 2 hours."*

### Your Interview Narrative (Memorise This)

> "I built GovPlatform UK — a secure AWS platform designed to support government-style digital services, modelled directly on how departments like DWP operate.
>
> The platform provides automated deployment pipelines, container orchestration on EKS, and a full security and compliance layer — so that development teams can ship services quickly without reinventing infrastructure.
>
> The platform handles four tenant services: user identity, claim processing, case management, and document upload. Each demonstrates a different platform pattern — stateful database services, event-driven processing with SQS, internal-only services with no public exposure, and secure document handling with S3 pre-signed URLs.
>
> Infrastructure is entirely Terraform-managed. The CI/CD pipeline uses GitHub Actions for fast feedback and CodePipeline for deployment governance — including approval gates before production. Deployments use Kubernetes rolling updates in dev and canary deployments in production, with automatic rollback if CloudWatch alarms fire.
>
> Security is layered: SCPs prevent disabling GuardDuty or CloudTrail at the organisation level. IAM permission boundaries prevent pipeline-created roles from exceeding their intended scope. AWS Config enforces 20+ compliance rules with auto-remediation. WAF protects every public endpoint with OWASP rules, rate limiting, and UK-only geo restriction.
>
> I can rebuild the entire platform from scratch using `terraform apply` and I have documented every design decision with lessons aimed at junior engineers I would be supporting on the team."

---

## Cost Guide

### Estimated Monthly Costs (Dev Account, eu-west-2)

| Service | Spec | Monthly Cost |
|---|---|---|
| EKS Control Plane | 1 cluster | ~£70 |
| EC2 Worker Nodes | 2× t3.medium Spot | ~£20 |
| RDS PostgreSQL | db.t3.micro, Multi-AZ OFF for dev | ~£15 |
| NAT Gateway | 1× (save cost in dev, use 3× in prod) | ~£35 |
| Application Load Balancer | 2× ALB | ~£18 |
| ECR | 4 repos, ~10GB storage | ~£8 |
| CloudWatch | Logs + metrics + dashboards | ~£15 |
| GuardDuty | ~5GB events/month | ~£10 |
| AWS Config | ~10,000 evaluations/month | ~£5 |
| Inspector v2 | ECR scanning | ~£5 |
| Secrets Manager | 10 secrets | ~£4 |
| S3, SSM, SQS | Various | ~£5 |
| **Total (Dev)** | | **~£210/month** |

### Cost-Saving Tips for Learning

1. **Use Spot instances for EKS nodes** — saves ~70% on EC2 cost. Spot nodes can be interrupted with 2-minute warning. Kubernetes reschedules pods automatically.

2. **Single NAT Gateway in dev** — losing HA is acceptable in dev. Saves ~£70/month (3 NAT GWs vs 1).

3. **Scale worker nodes to 0 overnight** — use an EventBridge rule to set ASG desired count to 0 at 8pm and back to 2 at 8am. Saves ~50% EC2 cost.

4. **RDS Single-AZ in dev** — Multi-AZ doubles RDS cost. Use single-AZ for learning, Multi-AZ for production simulation.

5. **Use AWS Free Tier where eligible** — some CloudWatch metrics, first 5GB of logs ingestion, etc.

---

## Next Steps After Completing This Project

1. **Deploy it** — follow `docs/deployment-guide.md` step by step
2. **Destroy and rebuild** — run `terraform destroy` then `terraform apply` — the ultimate IaC confidence test
3. **Break it intentionally** — kill pods, terminate nodes, delete secrets — watch the platform recover
4. **Add GitOps** — replace `kubectl apply` with ArgoCD for a more advanced deployment pattern
5. **Add a service mesh** — AWS App Mesh for mTLS between services
6. **Write your personal statement** — map every section of this project to a criterion in the job spec

---

## Useful Resources

| Resource | What It Teaches |
|---|---|
| [AWS EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/) | EKS security, scalability, reliability |
| [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) | Every AWS resource in Terraform |
| [NCSC Cloud Security Principles](https://www.ncsc.gov.uk/collection/cloud/the-cloud-security-principles) | What DWP's security team evaluates against |
| [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/) | The five pillars DWP will ask about |
| [Kubernetes Documentation](https://kubernetes.io/docs/) | Understanding every manifest field |

---

*Built for DWP Senior AWS DevOps Engineer interview preparation.*
*Every decision documented. Every lesson included. Deploy it, break it, rebuild it.*
