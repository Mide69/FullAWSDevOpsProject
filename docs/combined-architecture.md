# Combined Architecture — Why We Built It This Way

## Two Perspectives, One Stronger Project

This project was designed by combining two complementary approaches:

| Perspective A (AWS-Native First) | Perspective B (Platform Engineering First) |
|---|---|
| Start with AWS services: CodeCommit, CodeBuild, CodeDeploy, CodePipeline | Start with the problem: what does a platform team actually build? |
| Proves AWS service depth (important for DWP) | Proves engineering thinking and system design |
| Strong for technical exercises and "what tool do you use" questions | Strong for "tell me about a platform you built" narrative |
| Risk: looks like a checklist of AWS services without a story | Risk: too abstract, not enough specific AWS depth |

**The combined result:** A platform with a clear purpose (support government services) that uses AWS-native tooling throughout, plus modern open-source tools where AWS does not have a native answer.

---

## Full Architecture Diagram (Text)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         AWS ORGANIZATIONS                                    │
│                                                                              │
│  ┌─────────────────┐    ┌──────────────────────────────────────────────┐    │
│  │  Management     │    │  GovPlatform OU                              │    │
│  │  Account        │    │                                              │    │
│  │                 │    │  ┌─────────────────┐  ┌──────────────────┐  │    │
│  │  Control Tower  │───►│  │  govplatform-   │  │  govplatform-    │  │    │
│  │  Landing Zone   │    │  │  dev account    │  │  prod account    │  │    │
│  │  SCPs           │    │  └────────┬────────┘  └──────────────────┘  │    │
│  │  Account        │    │           │ (this project)                   │    │
│  │  Factory        │    └───────────┼──────────────────────────────────┘    │
│  └─────────────────┘                │                                        │
└─────────────────────────────────────┼────────────────────────────────────────┘
                                       │
                    ┌──────────────────▼─────────────────────┐
                    │         govplatform-dev Account          │
                    │                                          │
  GitHub ──────────►│  GitHub Actions (Build + Test + Scan)   │
  (source of truth) │         │                               │
                    │         ▼                               │
                    │     AWS ECR                             │
                    │   (container images)                    │
                    │         │                               │
                    │         ▼                               │
                    │  CodePipeline ──► Manual Approval       │
                    │  (deploy governance)  (for prod)        │
                    │         │                               │
                    │         ▼                               │
                    │  ┌──────────────────────────────────┐  │
                    │  │         VPC (eu-west-2)           │  │
                    │  │                                   │  │
                    │  │  Public Subnets (3 AZs)           │  │
                    │  │  ┌────────────────────────────┐   │  │
                    │  │  │  ALB (HTTPS + WAF)         │   │  │
                    │  │  └──────────────┬─────────────┘   │  │
                    │  │                 │                  │  │
                    │  │  Private Subnets (3 AZs)           │  │
                    │  │  ┌──────────────▼─────────────┐   │  │
                    │  │  │  EKS Cluster                │   │  │
                    │  │  │                             │   │  │
                    │  │  │  user-service (2 pods)      │   │  │
                    │  │  │  claim-service (2 pods)     │   │  │
                    │  │  │  case-service (2 pods)      │   │  │
                    │  │  │  document-service (2 pods)  │   │  │
                    │  │  │                             │   │  │
                    │  │  │  (Fluent Bit, X-Ray, ESO)  │   │  │
                    │  │  └──────────────┬─────────────┘   │  │
                    │  │                 │                  │  │
                    │  │  Data Subnets (3 AZs)              │  │
                    │  │  ┌──────────────▼─────────────┐   │  │
                    │  │  │  RDS PostgreSQL (Multi-AZ)  │   │  │
                    │  │  │  ElastiCache Redis          │   │  │
                    │  │  └────────────────────────────┘   │  │
                    │  └──────────────────────────────────┘  │
                    │                                          │
                    │  Security Plane:                        │
                    │  GuardDuty → Security Hub → SNS → Email │
                    │  Config Rules → Auto-Remediation        │
                    │  CloudTrail → S3 (90 days)              │
                    │  WAF → CloudWatch → Alarms              │
                    │                                          │
                    │  Observability Plane:                   │
                    │  EKS Container Insights → CloudWatch    │
                    │  Fluent Bit → CloudWatch Logs           │
                    │  X-Ray → Service Map + Traces           │
                    │  Synthetics Canary → Uptime Monitoring  │
                    └──────────────────────────────────────────┘
```

---

## Why EKS Instead of ECS?

> This is a question you WILL be asked. Have the answer ready.

**ECS Fargate** (original project):
- Simpler to operate — AWS manages the control plane AND the node lifecycle
- Lower operational overhead
- Strong for teams that want "just run my containers"
- Less flexibility: harder to run custom admission controllers, service meshes, etc.

**EKS** (combined project):
- Industry standard — Kubernetes skills transfer across cloud providers and on-premise
- DWP and most large government departments already have or are moving to Kubernetes
- Required for advanced patterns: pod-level network policies, custom operators, GitOps with ArgoCD
- IRSA is more granular than ECS task roles

**The honest answer for the interview:**
> "I chose EKS because it represents how large enterprises like DWP actually run containers at scale. The operational overhead is higher, but the flexibility to implement network policies, pod-level IAM via IRSA, and GitOps patterns outweighs that cost. For a smaller team or simpler workloads, I would choose ECS Fargate — it's excellent for straightforward deployments."

Showing you can make AND justify the trade-off is more impressive than just knowing one option.

---

## Why Both GitHub Actions AND CodePipeline?

```
Developer pushes commit
      │
      ▼
GitHub Actions (< 3 minutes)
├── Fast feedback to developer
├── Lint + unit tests
├── Trivy container scan
├── Semgrep SAST
├── Checkov IaC scan
├── Build Docker image
└── Push to ECR (tagged with git SHA)
      │
      ▼ (on merge to main)
AWS CodePipeline (deployment governance)
├── Source: ECR image exists? → yes
├── Build: update K8s manifests with new image tag
├── Deploy Dev: kubectl apply → wait for rollout → smoke test
├── Manual Approval (email via SNS)
└── Deploy Prod: canary 10% → alarms OK → 100%
```

**Why split them?**
- GitHub Actions runs on every commit and PR. Fast feedback is critical for developer productivity.
- CodePipeline is the audit trail for deployments. Every deployment to production has an approval record. This is a regulatory requirement in government.
- CodePipeline integrates natively with CodeDeploy for blue/green — no third-party plugins.

**What to say in the interview:**
> "We use GitHub Actions for the build, test, and scan stage because it gives developers instant feedback on their PR. We use CodePipeline for the deployment stage because it gives us a full audit trail, approval gates, and native integration with AWS CodeDeploy for blue/green deployments. The two tools complement each other."

---

## Why Control Tower?

Control Tower solves a real problem you will face at DWP:

**Without Control Tower:**
- New project → someone manually creates an AWS account
- Security team applies guardrails manually (or forgets)
- Accounts drift from standard configuration over time
- Billing is opaque — hard to attribute costs to teams

**With Control Tower:**
- New project → self-service Account Factory form → account ready in 20 minutes with ALL guardrails pre-applied
- Every account is identical: CloudTrail enabled, GuardDuty enabled, SCPs enforced
- AWS SSO (IAM Identity Center) gives engineers access without IAM users
- AWS Organizations enables centralised billing

**What DWP actually does:**
Large government departments use Landing Zone patterns extensively. The Cyber Essentials and NCSC Cloud Security Principles require controls that Control Tower enforces automatically. Knowing how to set this up demonstrates the kind of thinking they need in a Senior engineer.

---

## The 3-Subnet Architecture — Why Data Subnets?

Many tutorials use 2 tiers: public + private. We use 3: public + private + data.

```
Public subnets:   ALB only — accepts internet traffic
Private subnets:  EKS nodes — runs application code
Data subnets:     RDS, ElastiCache — stores sensitive data
```

Why the third tier?

1. **Network isolation:** A compromised application pod in private subnets cannot directly reach the database if a security group rule is the only protection. But if an attacker gains control of the security group (e.g., via a misconfigured Lambda), the data subnet NACL provides a second layer.

2. **Compliance:** PCI-DSS, ISO 27001, and NCSC guidelines all recommend this separation. A DWP security review would expect it.

3. **Clarity:** It is obvious from the architecture diagram what each subnet tier is for. Infrastructure should communicate its design intent.

---

## How the Services Communicate

```
Internet
    │ (HTTPS/443)
    ▼
WAF → ALB → Ingress Controller (in EKS)
    │
    ├──► user-service:3000
    ├──► claim-service:8080
    └──► document-service:4000

case-service:8080  ← NO public route (internal only)
    │
    └──► user-service:3000 (via Kubernetes service DNS)

All inter-service calls use:
- Kubernetes ClusterIP services (internal DNS: user-service.default.svc.cluster.local)
- mTLS via AWS App Mesh (optional, advanced)
- No hard-coded IP addresses anywhere
```

**Security implication:** The case management service has NO ALB. It cannot be reached from the internet under any circumstances — not by misconfiguration, not by a forgotten security group rule. The architecture enforces this.

---

## Key Design Decisions Summary

| Decision | Chosen Approach | Why | Alternative |
|----------|----------------|-----|-------------|
| Container orchestration | EKS | Industry standard, IRSA, Kubernetes ecosystem | ECS Fargate — simpler, less overhead |
| CI/CD | GitHub Actions + CodePipeline | Fast feedback + governance + audit trail | Jenkins, GitLab CI |
| IaC | Terraform (infra) + CDK (pipelines) + SAM (Lambda) | Right tool for each layer | Pure Terraform or pure CDK |
| Secrets | Secrets Manager + External Secrets Operator | Rotation + Kubernetes native sync | SSM Parameter Store only |
| Deployment strategy | Canary (prod) + Rolling (dev) | Gradual risk + easy rollback | Blue/green (more resource cost) |
| Account strategy | Control Tower + separate practice account | Real enterprise pattern + isolation | Single account |
| Subnet design | 3-tier (public/private/data) | Compliance, defence in depth | 2-tier |
| Image tags | Immutable (git SHA) | Reproducibility, no accidental overwrites | Mutable :latest |
| Logging | Fluent Bit → CloudWatch | Managed, no extra infra | EFK stack (expensive, complex) |
| Monitoring | CloudWatch + X-Ray + Grafana | AWS-native + visual dashboards | Datadog, New Relic |
