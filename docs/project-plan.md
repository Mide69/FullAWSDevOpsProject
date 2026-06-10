# Project Plan — GovPlatform UK
## Full AWS DevOps Learning Programme

**Goal:** Build production-grade skills for DWP Senior AWS DevOps Engineer role  
**Target Date:** Interview preparation complete  
**AWS Setup:** Control Tower landing zone with dedicated practice account  

---

## Phase 0: Foundation (Do This First)

> **Why this phase exists:** Everything after this depends on it. A shaky foundation means every subsequent phase becomes debugging infrastructure instead of learning DevOps.

### 0.1 — AWS Control Tower Setup
- [ ] Enable Control Tower in your master/management account
- [ ] Create "GovPlatform" Organisational Unit (OU)
- [ ] Vend a new AWS account: `govplatform-dev` via Account Factory
- [ ] Enable the following guardrails (SCPs):
  - Disallow root account usage
  - Require CloudTrail enabled
  - Disallow disabling GuardDuty
  - Restrict to UK regions (eu-west-2, eu-west-1)
- [ ] Set up AWS SSO (IAM Identity Center) for cross-account access

**What you learn:** Account vending, landing zone design, SCPs, AWS Organizations

### 0.2 — Terraform State Bootstrap
In the NEW `govplatform-dev` account:
- [ ] Create S3 bucket for Terraform state (versioned, encrypted)
- [ ] Create DynamoDB table for state locking
- [ ] Create KMS key for state encryption
- [ ] Store bootstrap script in `infrastructure/terraform/bootstrap/`

**What you learn:** Terraform remote state, the chicken-and-egg problem of bootstrapping IaC

### 0.3 — GitHub Repository Setup
- [ ] Configure GitHub OIDC provider in AWS (no long-lived access keys)
- [ ] Create IAM role for GitHub Actions with permission boundary
- [ ] Set branch protection rules: require PR + 1 reviewer before merge to main
- [ ] Configure Dependabot for dependency scanning

**What you learn:** OIDC federation (modern alternative to IAM user keys), branch governance

**Deliverable:** You can run `terraform plan` from your laptop against the dev account and GitHub Actions can push to ECR.

---

## Phase 1: Core Infrastructure (Week 1–2)

> **Why this order:** You build the "ground" before the "building". VPC before EKS. EKS before services.

### 1.1 — Networking (Terraform)
- [ ] VPC: 3 AZs, public + private + data subnets
- [ ] NAT Gateways (one per AZ for HA)
- [ ] VPC Flow Logs → S3 (with 90-day lifecycle)
- [ ] Security Groups: ALB, EKS nodes, RDS
- [ ] VPC Endpoints: S3, ECR, SSM, Secrets Manager (saves NAT costs + improves security)

**Lesson:** VPC Endpoints mean your EKS pods pull container images from ECR without going through the internet. Faster AND more secure.

### 1.2 — EKS Cluster (Terraform)
- [ ] EKS cluster: Kubernetes 1.29+, private API endpoint
- [ ] Managed node groups: on-demand (t3.medium) for system, Spot (t3.medium/large) for workloads
- [ ] Cluster autoscaler or Karpenter
- [ ] AWS Load Balancer Controller (Helm)
- [ ] EBS CSI driver (for persistent volumes)
- [ ] IRSA (IAM Roles for Service Accounts) — NOT kube2iam

**Lesson:** IRSA gives each Kubernetes service account its own IAM role. This means a compromised pod in Service A cannot access Service B's database. This is least-privilege applied to containers.

### 1.3 — ECR Repositories
- [ ] One repo per service: `govplatform/user-service`, `govplatform/claim-service`, etc.
- [ ] Immutable image tags
- [ ] Image scanning on push (Inspector v2)
- [ ] Lifecycle policy: keep last 20 tagged images

### 1.4 — Secrets and Configuration
- [ ] AWS Secrets Manager: database credentials per service
- [ ] SSM Parameter Store: non-secret config (URLs, queue names, feature flags)
- [ ] External Secrets Operator in EKS (syncs Secrets Manager → Kubernetes Secrets)

**Lesson:** Never mount Secrets Manager credentials directly as environment variables in a task definition if you can avoid it. Use External Secrets Operator so Kubernetes handles the sync and rotation automatically.

### 1.5 — RDS Database (PostgreSQL)
- [ ] Multi-AZ RDS PostgreSQL 15 in private data subnets
- [ ] Encryption at rest (KMS)
- [ ] Automated backups: 7-day retention
- [ ] Parameter group: SSL required
- [ ] Credentials in Secrets Manager with auto-rotation

**Deliverable:** `terraform apply` creates the full network and compute layer. EKS cluster is accessible. You can run `kubectl get nodes`.

---

## Phase 2: First Service — User Service (Week 2–3)

> **Why start here:** It is the simplest service. Master deployment here and the rest follow the same pattern.

### 2.1 — Build the Service
Language: Node.js (Express) or Python (FastAPI) — your choice

Endpoints:
```
GET  /health           → { status: "healthy", version: "1.0.0" }
POST /users            → Create user (name, email)
GET  /users/:id        → Get user by ID
GET  /api-docs         → OpenAPI/Swagger UI
```

Requirements:
- [ ] Structured JSON logs (use `pino` for Node or `structlog` for Python)
- [ ] Database connection via PostgreSQL (pg or asyncpg)
- [ ] Credentials loaded from environment (injected by External Secrets from Secrets Manager)
- [ ] `/health` checks DB connectivity
- [ ] OpenAPI spec generated automatically

### 2.2 — Containerise It Properly
- [ ] Multi-stage Dockerfile (builder + runtime)
- [ ] Non-root user
- [ ] `readonlyRootFilesystem: true` in Kubernetes manifest
- [ ] HEALTHCHECK instruction
- [ ] Image under 200MB (use alpine base)

### 2.3 — Local Testing First (Before AWS)
- [ ] `docker-compose.yml` with service + postgres
- [ ] Runs locally with `docker compose up`
- [ ] All endpoints tested manually
- [ ] Unit tests pass: `npm test` or `pytest`

**Lesson:** If you cannot run it locally, you cannot debug it in AWS. Docker Compose is the fastest debugging loop.

### 2.4 — Kubernetes Manifests
```
k8s/user-service/
├── deployment.yaml       # 2 replicas, resource limits, liveness/readiness probes
├── service.yaml          # ClusterIP (internal only)
├── ingress.yaml          # ALB Ingress via AWS Load Balancer Controller
├── hpa.yaml              # Horizontal Pod Autoscaler (CPU 70%)
├── pdb.yaml              # PodDisruptionBudget (min 1 available)
└── serviceaccount.yaml   # IRSA-linked SA for DB access
```

**Lesson:** The PodDisruptionBudget ensures Kubernetes never takes down ALL pods at once during a node drain or rolling update. Without this, a cluster upgrade could cause downtime.

**Deliverable:** `kubectl apply -f k8s/user-service/` deploys the service. You can hit the health endpoint through the ALB.

---

## Phase 3: CI/CD Pipeline (Week 3–4)

> **Why this order:** You need a working service before you can build a pipeline for it. Now you know exactly what the pipeline needs to do.

### 3.1 — GitHub Actions Pipeline (Build + Test + Scan)

```yaml
# Triggers on: push to main, PR to main
Jobs (in parallel):
  lint-and-test:    → eslint/flake8 + jest/pytest
  security-scan:    → Trivy (container) + Semgrep (SAST) + detect-secrets
  build-and-push:   → docker build → ECR push (tag: git SHA)
  iac-scan:         → Checkov on Terraform + K8s manifests
```

### 3.2 — CodePipeline + CodeDeploy (AWS-side deployment)

```
Source: GitHub (via CodeStar connection) OR CodeCommit mirror
  ↓
CodeBuild: pull image from ECR + update K8s deployment manifest
  ↓
Manual Approval (for prod)
  ↓
CodeBuild: kubectl apply to EKS + wait for rollout
  ↓
Post-deploy: smoke tests via Lambda lifecycle hook
```

**Why both GitHub Actions AND CodePipeline?**
- GitHub Actions = developer-facing (fast feedback on PR)
- CodePipeline = deployment governance (audit trail, approval gates, AWS-native)
- DWP will use one or both — showing both proves breadth

### 3.3 — Deployment Strategy: Rolling Update (Dev) → Blue/Green (Prod)

Dev environment:
- Kubernetes rolling update (default)
- 25% max unavailable, 25% max surge

Production:
- AWS CodeDeploy with ECS or use Argo Rollouts with canary for EKS
- 10% canary → CloudWatch alarm evaluation (5 min) → 100% shift

### 3.4 — Rollback Strategy
Automatic triggers:
- CloudWatch alarm: P99 > 2s OR 5xx > 1%
- Liveness probe failures > 3 consecutive
Manual:
- `kubectl rollout undo deployment/user-service`
- CodeDeploy: stop + rollback button

**Deliverable:** Push a commit to `main`. Within 8 minutes: GitHub Actions builds and scans, CodePipeline deploys to dev, smoke tests pass. A broken commit triggers rollback automatically.

---

## Phase 4: Remaining Services (Week 4–5)

Follow the same pattern as User Service for each:

### Claim Processing Service
Additional elements:
- [ ] SQS queue for async processing
- [ ] S3 bucket for claim documents
- [ ] EventBridge rule: claim submitted → notification Lambda
- [ ] DynamoDB for claim status tracking (fast reads)

### Case Management Service
Additional elements:
- [ ] Internal-only (no public ALB — uses internal NLB or ClusterIP only)
- [ ] Demonstrates network segmentation: case service CAN talk to user service, cannot reach claim service's SQS directly

### Document Upload Service
Additional elements:
- [ ] S3 pre-signed URL generation (5-minute expiry)
- [ ] Lambda: scan uploaded file with ClamAV layer before making accessible
- [ ] S3 event → Lambda → quarantine if virus found

**Lesson:** Pre-signed URLs mean citizens upload directly to S3 from their browser. Your service never receives the file data — it just generates a temporary upload URL. This is both faster and cheaper.

---

## Phase 5: Security Hardening (Week 5–6)

> **This is where DWP Senior roles are won or lost.** Junior candidates deploy. Senior candidates secure.

### 5.1 — Identity and Access Management
- [ ] Permission boundaries on ALL roles created by pipelines
- [ ] No IAM users in production account (SSO only)
- [ ] IRSA for every service account in EKS
- [ ] Service Control Policies reviewed and tested
- [ ] Access Analyzer: scan for over-permissive policies

### 5.2 — Encryption
- [ ] All S3 buckets: SSE-KMS (customer-managed key)
- [ ] RDS: encrypted with KMS
- [ ] EBS volumes: encrypted
- [ ] Secrets Manager: encrypted with KMS
- [ ] ALB: TLS 1.2+ only, modern cipher policy

### 5.3 — Threat Detection
- [ ] GuardDuty: enabled, findings → EventBridge → SNS → email
- [ ] Security Hub: enabled, aggregate findings from GuardDuty + Config + Inspector
- [ ] Inspector v2: ECR image scanning + Lambda function scanning
- [ ] Macie: scan S3 buckets for PII (Personal Identifiable Information — critical for DWP)

### 5.4 — Compliance Monitoring
- [ ] AWS Config: 20+ managed rules across compute, network, IAM, encryption
- [ ] Auto-remediation for critical rules (public S3 → auto-block)
- [ ] Config conformance pack: NIST 800-53 or Cyber Essentials aligned
- [ ] Weekly compliance report via Lambda → email

### 5.5 — Network Security
- [ ] WAF on every public ALB: OWASP Core + rate limiting + geo restriction (UK only)
- [ ] VPC NACLs: additional layer (deny common attack ranges)
- [ ] No security groups with `0.0.0.0/0` inbound except port 443 on ALB
- [ ] AWS Network Firewall: outbound filtering (EKS pods cannot call arbitrary internet)

**Deliverable:** Security Hub score > 80%. Zero "CRITICAL" findings. CloudTrail shows every API call ever made.

---

## Phase 6: Observability (Week 6–7)

### 6.1 — Metrics
- [ ] Container Insights enabled on EKS
- [ ] Custom application metrics (request count, latency, error rate) via CloudWatch EMF
- [ ] CloudWatch dashboards: one per service + one platform overview
- [ ] Alarms: CPU, memory, error rate, latency, pod restart count

### 6.2 — Logs
- [ ] Fluent Bit DaemonSet → CloudWatch Logs
- [ ] Structured log format (JSON): every log line includes service, version, traceId, userId
- [ ] Log Insights queries saved as named queries
- [ ] Log retention: 30 days hot, archive to S3 Glacier after 90 days

### 6.3 — Traces
- [ ] AWS X-Ray in all services
- [ ] Service Map shows: ALB → User Service → RDS
- [ ] Trace sampling: 5% general, 100% for errors
- [ ] X-Ray groups for filtering by service

### 6.4 — Alerting
- [ ] SNS topics per severity: P1-critical, P2-high, P3-medium
- [ ] On-call runbook linked from every alarm description
- [ ] Alarm suppression during maintenance windows (EventBridge schedule)
- [ ] CloudWatch Synthetics canary: runs every 5 min, tests full user journey

### 6.5 — Grafana (Bonus — demonstrates modern tooling)
- [ ] Amazon Managed Grafana workspace
- [ ] CloudWatch data source
- [ ] Import standard EKS dashboard
- [ ] Share dashboard URL in interview

**Deliverable:** You can answer "what happened between 14:00 and 14:05 yesterday?" using metrics + logs + traces. This is what being on-call actually requires.

---

## Phase 7: Interview Preparation (Week 7–8)

### 7.1 — Technical Exercise Preparation
The job spec says: *"You will be asked to do a 10 minute technical exercise on a specific topic."*

Likely topics:
- Write a CodeBuild buildspec for a Node.js app
- Fix a broken Terraform module
- Write a Kubernetes deployment with resource limits
- Design a CI/CD pipeline for a given scenario
- Review a CloudFormation template for security issues

Practice: Set a 10-minute timer. Write from memory. Repeat weekly.

### 7.2 — Behavioural Evidence (STAR format)
Map real examples to each essential criterion:

| Criterion | Your Story |
|-----------|------------|
| IaC knowledge | "I built Terraform modules for VPC, EKS, and monitoring that are reused across dev/prod..." |
| Unix/Linux scripting | "I wrote bash scripts for deployment with error handling, AWS CLI, and jq..." |
| CI/CD experience | "I designed a dual pipeline: GitHub Actions for fast feedback + CodePipeline for deployment governance..." |
| Guiding engineers | "I documented every design decision in architecture.md with junior-friendly explanations..." |
| AWS cloud-based apps | "I built and operated a 4-service platform on EKS with full observability and automated security compliance..." |

### 7.3 — Personal Statement Draft
Draft against each essential criterion in the job spec. 750 words max.

---

## Costs Estimate (Monthly — Dev Account)

| Service | Estimate |
|---------|----------|
| EKS Cluster | ~£70 |
| EC2 (2× t3.medium workers) | ~£50 |
| RDS db.t3.micro Multi-AZ | ~£30 |
| NAT Gateways (3) | ~£100 |
| ALB | ~£20 |
| CloudWatch, CloudTrail | ~£15 |
| ECR, S3, SSM | ~£5 |
| GuardDuty, Config, SecurityHub | ~£25 |
| **Total** | **~£315/month** |

> **Cost saving tip:** Shut down EKS worker nodes after hours using an EventBridge schedule. Use Spot instances for worker nodes (70% cheaper). Keep RDS running — stop/start causes issues with connection pools.

---

## Success Criteria (Interview Ready)

You are ready when you can do ALL of these:

- [ ] Destroy and rebuild the entire platform from scratch using `terraform apply` (the ultimate IaC test)
- [ ] Explain why you chose every major design decision (not just what it does)
- [ ] Walk through the full deployment pipeline live — from `git push` to service running in EKS
- [ ] Demonstrate a rollback: push a broken service, watch it auto-rollback, explain why
- [ ] Show the Security Hub dashboard and explain each control
- [ ] Write a buildspec.yml from memory in 10 minutes
- [ ] Answer "how would you onboard a new team onto this platform?"
