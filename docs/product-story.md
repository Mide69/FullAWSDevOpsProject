# Product Story — GovPlatform UK

> *"The platform that powers digital government services — so that teams build fast and citizens are always served."*

---

## The One-Line Summary

GovPlatform UK is a secure, automated cloud platform that lets government development teams deploy and run digital services safely, at scale, without needing to understand the underlying infrastructure.

---

## The Problem We Are Solving

### The world before this platform

Imagine you are a developer at a government department.

You have just been asked to build a new service — something citizens will use to apply for a benefit, upload a document, or check the status of their claim.

Here is what happens without a platform like this:

- You spend the first **3 weeks** just setting up AWS accounts, VPCs, and permissions — before writing a single line of code.
- Every team does this differently. One team uses CloudFormation. Another uses the AWS console (by hand). A third has a 200-line bash script that nobody understands.
- When something breaks in production at 2am, nobody knows where the logs are, or whether GuardDuty is even turned on.
- Secrets (database passwords, API keys) are sometimes stored in Git. Sometimes in a shared spreadsheet. Nobody is proud of this.
- A security audit finds 47 open issues. Fixing them takes 3 months because each service was set up differently.
- Deploying to production requires emailing a "change management" board and waiting 2 weeks for approval.

**The result:** slow delivery, inconsistent security, frustrated engineers, and citizens waiting longer than they should for services they need.

---

### The world with GovPlatform UK

The same developer now:

1. Requests a new AWS account via a self-service form → it is provisioned in 20 minutes with all security guardrails pre-configured (Control Tower).
2. Clones a starter template, writes their service, pushes to GitHub.
3. A pipeline automatically tests, scans for vulnerabilities, builds a Docker image, and deploys to the platform.
4. The service is running in EKS with monitoring, logging, and alerting pre-wired.
5. If something breaks in production, there is a dashboard showing exactly what failed and why, and the service automatically restarts.
6. A security report is generated every week showing compliance across every service on the platform.

**The result:** teams ship in days not months. Security is consistent and auditable. Citizens get better services faster.

---

## Who Uses This Platform

### Primary Users

**1. Developer Teams (the builders)**
- 5–15 people teams building specific government services
- They want: "I push code, it goes live safely. I don't want to think about AWS."
- Pain point today: each team re-invents infrastructure from scratch

**2. Platform Engineers (us — the people building this project)**
- Responsible for the platform itself
- They want: everything standardised, auditable, and automatable
- This project IS the platform engineer's work product

**3. Security and Compliance Teams**
- Government has strict compliance requirements (Cyber Essentials, ISO 27001, NCSC guidelines)
- They want: proof that every service meets standards, without manually reviewing each one
- They will look at Security Hub dashboards and Config compliance reports

**4. Operations / SRE Teams**
- On-call when things break
- They want: runbooks, dashboards, alerts, and the ability to roll back a bad deployment in under 5 minutes

**5. Citizens (the ultimate end users)**
- Never interact with this platform directly
- But every second of downtime or data breach directly harms them

---

## The Services Running on the Platform

We are building the platform, not these services — but we use them to prove the platform works.

Think of these as the "tenant services" — small, realistic, government-flavoured applications that demonstrate every part of the platform.

### Service 1: User Identity Service
**What it does:** Manages citizen and agent accounts — create, retrieve, update.
**Why it matters to the platform:** Represents a stateful service with a database. Tests IAM roles, secrets management, RDS connectivity, and health checks.

### Service 2: Claim Processing Service
**What it does:** Accepts benefit claim submissions, validates them, stores them.
**Why it matters to the platform:** Represents a write-heavy service. Tests message queuing (SQS), event-driven architecture, and document storage (S3).

### Service 3: Case Management Service
**What it does:** Agents use this to view and update citizen cases.
**Why it matters to the platform:** Represents an internal-facing service. Tests network segmentation — this service is never publicly accessible.

### Service 4: Document Upload Service
**What it does:** Citizens upload evidence documents (PDFs, images) for their claims.
**Why it matters to the platform:** Tests S3 pre-signed URLs, file scanning (antivirus), and large object handling.

> **Important:** We are not building full applications. We are building *just enough* of each service to prove the platform capabilities work.

---

## What "Success" Looks Like

We will know the platform is working when:

| Goal | How We Measure It |
|------|-------------------|
| A developer can deploy a new service | From first commit to running in AWS in under 30 minutes |
| Every deployment is auditable | Full CloudTrail trail + pipeline logs retained for 1 year |
| Security posture is measurable | Security Hub score above 80% |
| Secrets are never in code | 0 findings from `detect-secrets` scan in any pipeline |
| Production deployments are safe | Blue/Green or canary — zero-downtime deployments |
| Incidents are detected quickly | CloudWatch alarm fires within 60 seconds of service degradation |
| Platform can be rebuilt from scratch | Full `terraform apply` from a clean account in under 2 hours |

---

## What Must Never Go Wrong

These are the non-negotiables. Everything else can be imperfect. These cannot:

1. **Citizen data must never be exposed** — encryption at rest and in transit everywhere, no exceptions.
2. **Production deployments must not cause downtime** — blue/green or canary deployments only.
3. **Security controls must not be bypassable** — SCPs prevent even account administrators from disabling GuardDuty or CloudTrail.
4. **Audit trail must always be intact** — CloudTrail cannot be disabled (enforced by SCP).
5. **IAM least privilege must be enforced** — no human has long-term console access to production.

---

## The Narrative for Your Interview

When a DWP interviewer asks *"Tell me about a platform you've built"*, your answer is:

> "I designed and built a secure AWS platform for government-style digital services, modelled on how departments like DWP actually operate. The platform uses Control Tower for account vending with pre-configured security guardrails, Terraform modules for consistent infrastructure provisioning, and dual CI/CD pipelines — GitHub Actions for the build and test phase, and CodePipeline with CodeDeploy for the AWS deployment workflow.
>
> Four tenant services run on the platform — a user identity service, claim processing, case management, and document upload. Each demonstrates a different platform capability: database connectivity, event-driven architecture, internal network segmentation, and secure file handling.
>
> The platform enforces security through layered controls: SCPs at the organisation level, IAM permission boundaries on every role, AWS Config rules with auto-remediation, GuardDuty and Security Hub for threat detection, and WAF protecting every public endpoint.
>
> When something goes wrong, the platform provides CloudWatch dashboards, X-Ray traces, and a tested runbook. Deployments use CodeDeploy Blue/Green with Lambda lifecycle hooks — meaning a bad deployment rolls back automatically within 60 seconds."

That answer demonstrates every single essential criterion in the DWP job spec.
