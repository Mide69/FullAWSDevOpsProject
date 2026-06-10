# Full AWS DevOps Project

A production-grade AWS DevOps reference project covering every major AWS DevOps service.
Built to demonstrate Senior-level capability for UK Government (DWP) interview preparation.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    FULL AWS DEVOPS PIPELINE                      │
│                                                                  │
│  Dev → CodeCommit → CodeBuild → CodeDeploy → ECS/EKS/Lambda     │
│          ↓              ↓            ↓                           │
│       Secrets        ECR         Blue/Green                      │
│       Manager      (Docker)      Deployment                      │
│          ↓              ↓            ↓                           │
│       SAST/SCA     DAST/OWASP   Smoke Tests                      │
│                                                                  │
│  Monitoring: CloudWatch → X-Ray → CloudTrail → GuardDuty        │
│  IaC:        Terraform + CDK + CloudFormation                    │
│  Security:   IAM + Config + SecurityHub + Inspector              │
└─────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
FullAWSDevOpsProject/
├── app/                        # Sample application (Node.js)
├── infrastructure/
│   ├── terraform/              # Terraform IaC - VPC, ECS, RDS, ALB
│   ├── cdk/                    # AWS CDK (TypeScript) - Lambda, API GW
│   └── cloudformation/         # CFN templates - legacy compatibility
├── cicd/
│   ├── buildspec/              # CodeBuild buildspec files
│   ├── pipeline/               # CodePipeline definitions (CFN + CDK)
│   └── scripts/                # Deployment helper scripts
├── security/
│   ├── iam/                    # IAM roles, policies, permission boundaries
│   ├── config-rules/           # AWS Config custom rules
│   ├── scp/                    # Service Control Policies
│   └── inspector/              # Amazon Inspector findings automation
├── monitoring/
│   ├── cloudwatch/             # Dashboards, alarms, log groups
│   ├── xray/                   # X-Ray sampling rules
│   └── synthetics/             # CloudWatch Synthetics canaries
├── containers/
│   ├── Dockerfile              # Multi-stage production Dockerfile
│   ├── ecs/                    # ECS task definitions
│   └── eks/                    # EKS manifests + Helm charts
├── serverless/
│   ├── lambda/                 # Lambda functions
│   └── sam/                    # SAM templates
├── networking/
│   ├── vpc/                    # VPC, subnets, NACLs, SGs
│   └── waf/                    # WAF WebACL rules
├── scripts/
│   ├── linux/                  # Linux/Bash automation scripts
│   └── windows/                # PowerShell scripts
├── tests/
│   ├── unit/                   # Unit tests
│   ├── integration/            # Integration tests
│   └── load/                   # Load tests (Artillery)
└── docs/
    ├── architecture.md
    ├── runbook.md
    └── security.md
```

## Services Covered

| Category | AWS Services |
|---|---|
| CI/CD | CodeCommit, CodeBuild, CodeDeploy, CodePipeline, CodeArtifact |
| Containers | ECR, ECS Fargate, EKS, App Mesh |
| Serverless | Lambda, API Gateway, SAM, Step Functions |
| IaC | CloudFormation, CDK, Systems Manager |
| Security | IAM, Secrets Manager, KMS, GuardDuty, SecurityHub, Inspector, Macie, WAF, Shield |
| Monitoring | CloudWatch, X-Ray, CloudTrail, Config, Trusted Advisor |
| Networking | VPC, ALB, Route53, CloudFront |
| Storage | S3, EFS, Parameter Store |
| Database | RDS, DynamoDB, ElastiCache |

## Quick Start

```bash
# 1. Deploy base infrastructure
cd infrastructure/terraform
terraform init && terraform apply -var-file=environments/dev.tfvars

# 2. Bootstrap CDK
cd infrastructure/cdk
npm install && cdk bootstrap && cdk deploy

# 3. Trigger pipeline
git push origin main   # CodePipeline auto-triggers
```

## Interview Preparation Notes

See [docs/architecture.md](docs/architecture.md) for deep-dives into each component.
