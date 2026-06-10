# Architecture Deep-Dive — Interview Reference

## 1. CI/CD Pipeline Flow

```
Developer pushes to CodeCommit (main branch)
    ↓
EventBridge rule fires → CodePipeline starts
    ↓
Stage 1: Source — CodeCommit checks out code
    ↓
Stage 2: Build + Security scan (PARALLEL CodeBuild actions)
  ├── BuildProject:
  │     npm install → lint → unit tests → docker build → ECR push
  │     → imagedefinitions.json artifact
  └── SecurityScanProject:
        Semgrep SAST → npm audit (SCA) → Checkov IaC scan → Trivy container scan
        → findings pushed to Security Hub
    ↓
Stage 3: Deploy to Dev (CodeDeploy Blue/Green to ECS Fargate)
  ├── Register new task definition
  ├── CodeDeploy shifts test traffic (10%) to green
  ├── Lambda hook runs smoke tests
  ├── If pass → shift 100% traffic → terminate blue
  └── If fail → auto-rollback to blue
    ↓
Stage 4: Manual Approval (SNS email to team lead)
    ↓
Stage 5: Deploy to Production (same Blue/Green process)
```

**Interview talking points:**
- "We use immutable ECR image tags tied to the Git commit SHA — no 'latest' in prod"
- "Build and security scan run in parallel to cut pipeline time by ~40%"
- "Blue/Green means zero-downtime deploys with instant rollback capability"
- "Lambda lifecycle hooks let us run automated smoke tests before traffic shifts"

---

## 2. Infrastructure as Code Strategy

| Tool | Use Case | Why |
|------|----------|-----|
| **Terraform** | Core infrastructure — VPC, ECS, RDS, ALB, WAF | State management, plan/apply workflow, team familiarity |
| **AWS CDK (TypeScript)** | Pipeline and Lambda constructs | Type-safe, reusable L2/L3 constructs, unit-testable |
| **CloudFormation** | Legacy compatibility, Config rules, WAF | Direct AWS native, some services only via CFN |
| **SAM** | Lambda-specific deployments | Local testing with `sam local`, simpler than raw CFN for functions |

**Key Terraform practices demonstrated:**
- Remote state in S3 with DynamoDB locking (prevents concurrent apply)
- KMS-encrypted state file
- Per-environment `.tfvars` files
- `validation` blocks on variables
- Module structure for reusability
- `default_tags` on provider (every resource tagged)

---

## 3. Security Architecture

### Defence in depth layers:

```
Internet → Shield Advanced (DDoS) → CloudFront → WAF WebACL
    ↓
ALB (HTTPS only, TLS 1.2+, ACM cert)
    ↓
Security Group (ALB → ECS task on port 3000 only)
    ↓
ECS Task (non-root user, readonlyRootFilesystem, no SSH)
    ↓
Secrets Manager (DB password) — never in env vars
Parameter Store (non-secret config)
KMS (envelope encryption for all data at rest)
```

### IAM approach — Least Privilege + Permission Boundaries:
- Every role has a **Permission Boundary** — prevents devs creating roles that exceed their own access
- ECS Task Role: only DynamoDB on its own tables + SSM on its own parameters + X-Ray
- CodeBuild Role: only ECR push to its repo + SSM read for `/devops/*` + Security Hub import
- No wildcard `Resource: "*"` except where unavoidable (e.g. `ecr:GetAuthorizationToken`)

### Continuous compliance:
- **AWS Config** — 15+ managed rules, auto-remediation for public S3 buckets
- **GuardDuty** — threat detection on all accounts, findings → EventBridge → Lambda → Jira
- **Security Hub** — aggregates Config + GuardDuty + Inspector + Macie
- **Inspector v2** — CVE scanning of ECR images on push
- **CloudTrail** — all API calls logged, encrypted, 90-day retention, CloudWatch alarms on suspicious actions
- **SCPs** — prevent root usage, disable CloudTrail/GuardDuty, non-approved regions, unencrypted S3 writes

---

## 4. Monitoring Strategy

### Three pillars:

**Metrics (CloudWatch)**
- ECS CPU/Memory utilization — alarm at 80%
- ALB 5xx count — alarm at >10/min
- ALB P99 latency — alarm at >2s
- Custom `ApplicationErrors` metric from log filter
- Auto-scaling triggers at 70% CPU

**Logs (CloudWatch Logs)**
- ECS container logs to `/ecs/<app>-<env>`
- VPC Flow Logs to S3 (90-day retention)
- ALB access logs to S3
- CloudTrail logs to S3 + CloudWatch
- Log Insights queries for error rate, slow queries, failed logins

**Traces (X-Ray)**
- Active tracing on ECS tasks via `aws-xray-sdk`
- 5% sampling rate, 100% for `/api/critical/*`
- Service map shows downstream DynamoDB, Secrets Manager calls
- Identifies P99 latency contributors across services

**Availability (CloudWatch Synthetics)**
- Canary runs every 5 minutes against `/health` endpoint
- Alarm if canary fails 2 consecutive checks
- Tests from multiple regions if using Route53 health checks

---

## 5. ECS Fargate Architecture

```
ALB (blue target group TG-1)   ALB (green target group TG-2)
         ↓                               ↓
  ECS Service (Blue)             ECS Service (Green) ← new deploy lands here
  Task: old image                Task: new image
  
CodeDeploy controls traffic shift:
  Canary: 10% green → wait 5min → 100% green → drain blue
  Linear: 10% per minute
  AllAtOnce: immediate (dev only)
```

**Fargate security:**
- No EC2 instances to patch
- `readonlyRootFilesystem: true` — container can't write to disk
- Non-root user in Dockerfile
- Secrets via `secrets:` in task definition (injected at runtime, not baked in image)
- Private subnets only — no public IP on tasks
- Outbound via NAT Gateway (auditable egress)

---

## 6. CodeDeploy Blue/Green — Interview Key Points

- **Zero downtime**: traffic shifts atomically, old version keeps running until drain completes
- **Instant rollback**: if alarms fire during bake period, CodeDeploy reverts in seconds
- **Lifecycle hooks**: Lambda functions run at each phase — pre-deploy health check, smoke tests, integration tests
- **Deployment configurations**:
  - `CodeDeployDefault.ECSCanary10Percent5Minutes` — safest for prod
  - `CodeDeployDefault.ECSLinear10PercentEvery1Minute` — gradual rollout
  - `CodeDeployDefault.ECSAllAtOnce` — fast, for dev only
- **Bake time**: keep traffic on green for N minutes before terminating blue — monitors alarms during this window

---

## 7. Linux/Windows Scripting Demonstrated

| Script | Language | Shows |
|--------|----------|-------|
| `deploy.sh` | Bash | `set -euo pipefail`, AWS CLI, polling loops, jq JSON manipulation |
| `setup-codecommit.sh` | Bash | Git credential helper, approval rules, trap for cleanup |
| `rotate-secrets.sh` | Bash | Secrets Manager rotation, ECS forced redeployment |
| `Deploy-Application.ps1` | PowerShell | CmdletBinding, error handling, AWS CLI, polling |
| `buildspec-*.yml` | YAML/Shell | CodeBuild multi-phase, parameter store integration |

---

## 8. Agile/DevOps Culture Points (for interview)

- **Engineering ownership**: developers own their pipelines end-to-end — no "throw over the wall"
- **Shift-left security**: SAST/SCA/IaC scan in the same pipeline stage as build, not a separate gate
- **Infrastructure as code review**: all Terraform changes go through PRs with 2-reviewer approval rule in CodeCommit
- **Runbooks as code**: incident response documented in `docs/runbook.md`, linked from CloudWatch alarms
- **Blameless post-mortems**: CodeDeploy rollback data + X-Ray traces provide full timeline for RCA
- **Platform team model**: this repo is a shared platform consumed by product teams via modules
