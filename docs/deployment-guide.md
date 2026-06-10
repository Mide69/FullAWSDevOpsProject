# Comprehensive Deployment Guide — GovPlatform UK
## Step-by-Step from Zero to Production-Ready Platform

> **Who this is for:** You have an existing AWS account and want to build a real, deployable platform for learning and interview preparation.
>
> **What "done" looks like:** You have a running EKS cluster in a dedicated AWS account (created by Control Tower), with 4 services deployed through an automated CI/CD pipeline, full security controls, and a monitoring dashboard.
>
> **Time estimate:** 2–3 days spread over 2–3 weeks if following the phases.

---

## Prerequisites — Do These Before Anything Else

### On your laptop:
```bash
# Check these are all installed before proceeding
aws --version          # >= 2.15
terraform --version    # >= 1.6
kubectl version --client  # >= 1.29
helm version           # >= 3.14
docker --version       # >= 24
git --version          # >= 2.40
node --version         # >= 20 (for CDK)
python3 --version      # >= 3.11
jq --version           # any recent version

# Install if missing (macOS)
brew install awscli terraform kubectl helm docker git node python3 jq

# Install if missing (Windows - run as Administrator)
winget install Amazon.AWSCLI HashiCorp.Terraform kubernetes-cli Helm.Helm Docker.DockerDesktop Git.Git OpenJS.NodeJS Python.Python.3.11
```

### AWS accounts needed:
1. **Management account** — your existing AWS account becomes this
2. **govplatform-dev account** — will be created by Control Tower in Step 1

### GitHub:
- Fork or clone this repository to your own GitHub account
- You need GitHub admin access (to configure OIDC and Actions secrets)

---

## PHASE 0: AWS Control Tower Setup

> **What you'll learn:** Account vending, Landing Zone design, SCPs, IAM Identity Center.
>
> **Why this matters for DWP:** Control Tower is how enterprise organisations manage hundreds of AWS accounts consistently. Senior engineers are expected to understand this pattern.

### Step 0.1 — Enable Control Tower in Your Management Account

**Warning:** Control Tower will create several resources in your management account. It is non-destructive but takes 60–90 minutes on first setup.

1. Log into your existing AWS account (this becomes the management account)
2. Set your home region to `eu-west-2` (London):
   - Top-right menu → region selector → EU (London)
3. Navigate to **AWS Control Tower** in the console
4. Click **"Set up landing zone"**
5. Configure:
   - **Home region:** eu-west-2
   - **Additional governed regions:** eu-west-1 (Ireland — for DR)
   - **Foundational OU name:** `Security`
   - **Additional OU:** Create one called `GovPlatform`
   - **Log archive account:** Create new — name it `govplatform-logs`
   - **Audit account:** Create new — name it `govplatform-audit`
   - **Enable AWS SSO (IAM Identity Center):** Yes

6. Click **"Set up landing zone"** — wait 60–90 minutes ☕

**What just happened?**
Control Tower created:
- An AWS Organisation with your account as the management account
- Two foundational accounts (log archive + audit) with security services pre-configured
- A `GovPlatform` Organisational Unit (OU) where your practice account will live
- AWS SSO with a default identity store
- Default preventive guardrails (SCPs) applied to all new accounts

**Lesson for junior engineers:**
> SCPs (Service Control Policies) work at the AWS Organisations level — they are like a ceiling on what any account in the OU can do. Even if an IAM administrator inside the account creates an `Allow *` policy, the SCP can still block specific actions. This is how an enterprise enforces non-negotiable controls without trusting each account administrator.

### Step 0.2 — Vend Your Practice Account

1. In Control Tower → **Account Factory** → **Enroll account**
2. Fill in:
   - **Account name:** `govplatform-dev`
   - **Account email:** use a + alias, e.g. `youremail+govplatform-dev@gmail.com`
   - **Display name:** `GovPlatform Dev`
   - **SSO user email:** your email
   - **OU:** `GovPlatform`
3. Click **Enroll account** — wait 15–20 minutes

**What just happened?**
A brand new AWS account was created, automatically enrolled in your Organisation, with:
- CloudTrail already enabled and logging to the log archive account
- GuardDuty enabled
- AWS Config enabled
- SCPs from the GovPlatform OU applied

You did not have to configure any of this manually. That's the power of Account Factory.

### Step 0.3 — Apply Custom SCPs to GovPlatform OU

In **AWS Organizations** → **Policies** → **Service Control Policies**:

Create a new SCP named `GovPlatformGuardrails` and paste the content from `security/scp/prevent-root-usage.json`.

Then attach it to the `GovPlatform` OU.

> **Test it works:** Log into the `govplatform-dev` account as an admin. Try to create a resource in `us-east-1`. It should be denied.

### Step 0.4 — Configure AWS SSO Access to Dev Account

1. **IAM Identity Center** → **AWS accounts** → select `govplatform-dev`
2. **Assign users or groups**
3. Create permission set: `DevOpsEngineerAccess`
4. Attach AWS managed policy: `AdministratorAccess` (for learning — restrict later)
5. Assign your SSO user to this permission set

Now you can access the dev account via the SSO portal without creating IAM users.

```bash
# Configure CLI access via SSO
aws configure sso
# Follow prompts: use the SSO start URL from IAM Identity Center
# Profile name: govplatform-dev

# Test access
aws sts get-caller-identity --profile govplatform-dev
```

**From now on, always use `--profile govplatform-dev` with AWS CLI commands, or:**
```bash
export AWS_PROFILE=govplatform-dev
```

---

## PHASE 1: Bootstrap Infrastructure

### Step 1.1 — Terraform State Bootstrap

> **Why bootstrap?** Terraform needs somewhere to store its state file. But that S3 bucket and DynamoDB table are themselves infrastructure. You have to create them before Terraform can manage everything else. This is the classic "bootstrap problem".

In the `govplatform-dev` account, run this ONE-TIME bootstrap script:

```bash
# Set your account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile govplatform-dev)
REGION="eu-west-2"

# Create S3 bucket for state
aws s3api create-bucket \
  --bucket "govplatform-terraform-state-${ACCOUNT_ID}" \
  --region $REGION \
  --create-bucket-configuration LocationConstraint=$REGION \
  --profile govplatform-dev

# Enable versioning (so you can recover from accidental state corruption)
aws s3api put-bucket-versioning \
  --bucket "govplatform-terraform-state-${ACCOUNT_ID}" \
  --versioning-configuration Status=Enabled \
  --profile govplatform-dev

# Block all public access
aws s3api put-public-access-block \
  --bucket "govplatform-terraform-state-${ACCOUNT_ID}" \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  --profile govplatform-dev

# Enable server-side encryption
aws s3api put-bucket-encryption \
  --bucket "govplatform-terraform-state-${ACCOUNT_ID}" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}' \
  --profile govplatform-dev

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name "govplatform-terraform-locks" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $REGION \
  --profile govplatform-dev

echo "Bootstrap complete. State bucket: govplatform-terraform-state-${ACCOUNT_ID}"
```

Save this as `infrastructure/terraform/bootstrap/bootstrap.sh` (it's already in this repo).

Now update `infrastructure/terraform/main.tf` — replace `ACCOUNT_ID` in the backend block:
```hcl
backend "s3" {
  bucket         = "govplatform-terraform-state-YOUR_ACCOUNT_ID"   # ← replace
  key            = "govplatform/terraform.tfstate"
  region         = "eu-west-2"
  encrypt        = true
  dynamodb_table = "govplatform-terraform-locks"
}
```

### Step 1.2 — Configure GitHub OIDC (No Long-Lived Keys)

> **Why OIDC?** Storing AWS access keys in GitHub Secrets is a security risk — they expire, get rotated incorrectly, or leak. OIDC lets GitHub Actions assume an IAM role temporarily for each job. No stored credentials anywhere.

```bash
# Create the OIDC identity provider for GitHub in your dev account
aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" \
  --profile govplatform-dev
```

Create the IAM role for GitHub Actions (`infrastructure/terraform/modules/github-actions-role/main.tf` — already in this repo):

```bash
cd infrastructure/terraform
terraform init
terraform apply -var="github_org=YOUR_GITHUB_USERNAME" -var="github_repo=FullAWSDevOpsProject"
```

This creates a role GitHub Actions can assume, with only the permissions it needs:
- ECR: push images
- EKS: update deployments
- SSM: read parameters
- CloudFormation: deploy stacks
- S3: read/write artifact bucket

Copy the role ARN output and add it to GitHub:
- **Repository Settings → Secrets and Variables → Actions**
- Add: `AWS_ROLE_ARN` = the role ARN
- Add: `AWS_REGION` = `eu-west-2`
- Add: `AWS_ACCOUNT_ID` = your account ID

> **Lesson:** Never put `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` in GitHub Secrets. OIDC is the correct pattern. If you see a team using long-lived keys in CI/CD, that's a finding.

### Step 1.3 — Deploy Networking

```bash
cd infrastructure/terraform
terraform init
terraform plan -var-file=environments/dev.tfvars -out=dev.plan
# Review the plan carefully — understand every resource being created
terraform apply dev.plan
```

Create `environments/dev.tfvars`:
```hcl
environment          = "dev"
aws_region           = "eu-west-2"
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
data_subnet_cidrs    = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
alarm_email          = "your-email@example.com"
certificate_arn      = ""  # leave empty for now, add ACM cert later
```

**After apply, verify:**
```bash
# Check VPC was created
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=dev-vpc" --profile govplatform-dev

# Check flow logs are enabled
aws ec2 describe-flow-logs --profile govplatform-dev

# Confirm 9 subnets (3 public + 3 private + 3 data)
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" \
  --query 'length(Subnets)' --profile govplatform-dev
# Should output: 9
```

**Lesson:** Always verify after apply. Terraform succeeding does not mean the resource does what you expect.

### Step 1.4 — Deploy EKS Cluster

```bash
# This takes 15–20 minutes
terraform apply -var-file=environments/dev.tfvars -target=module.eks
```

After apply:
```bash
# Configure kubectl to talk to your new cluster
aws eks update-kubeconfig \
  --region eu-west-2 \
  --name govplatform-dev \
  --profile govplatform-dev

# Verify nodes are ready
kubectl get nodes
# Should show 2–3 nodes in Ready state

# Verify system pods are running
kubectl get pods -n kube-system
```

> **If nodes are "NotReady":** Wait 3–5 more minutes. EKS nodes take time to register.

> **If `kubectl` returns "Unauthorized":** Check that your IAM role has the `eks:DescribeCluster` permission and that it was added to the EKS auth config. The Terraform module handles this automatically, but check the `aws-auth` ConfigMap:
> ```bash
> kubectl describe configmap aws-auth -n kube-system
> ```

### Step 1.5 — Install EKS Add-ons

```bash
# AWS Load Balancer Controller (creates ALBs from Kubernetes Ingress resources)
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=govplatform-dev \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# External Secrets Operator (syncs Secrets Manager → Kubernetes Secrets)
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace

# Metrics Server (required for HPA autoscaling)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Fluent Bit (sends container logs to CloudWatch)
helm repo add fluent https://fluent.github.io/helm-charts
helm install fluent-bit fluent/fluent-bit -n logging --create-namespace \
  --set cloudWatch.enabled=true \
  --set cloudWatch.region=eu-west-2 \
  --set cloudWatch.logGroupName=/eks/govplatform-dev

# Verify all add-ons are running
kubectl get pods -n kube-system
kubectl get pods -n external-secrets
kubectl get pods -n logging
```

**Lesson:** These are called "cluster add-ons" — they are not your application code, they are platform infrastructure that runs inside EKS. Every pod in EKS will benefit from Fluent Bit logging without any per-service configuration.

---

## PHASE 2: Deploy the User Service

### Step 2.1 — Create ECR Repository

```bash
aws ecr create-repository \
  --repository-name govplatform/user-service \
  --image-tag-mutability IMMUTABLE \
  --image-scanning-configuration scanOnPush=true \
  --region eu-west-2 \
  --profile govplatform-dev

# Note the repository URI — you'll need it
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile govplatform-dev)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.eu-west-2.amazonaws.com/govplatform/user-service"
echo "ECR URI: $ECR_URI"
```

### Step 2.2 — Build and Test Locally

```bash
cd services/user-service   # (you'll build this service)

# Run locally first
docker compose up

# In another terminal
curl http://localhost:3000/health
# Expected: {"status":"healthy","version":"1.0.0","db":"connected"}

curl -X POST http://localhost:3000/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"test@example.com"}'
# Expected: {"id":"uuid...","name":"Test User","email":"test@example.com"}
```

**Never deploy to AWS without testing locally first.** The iteration cycle locally (seconds) is far faster than the iteration cycle in AWS (minutes).

### Step 2.3 — Build and Push to ECR

```bash
# Login to ECR
aws ecr get-login-password --region eu-west-2 --profile govplatform-dev | \
  docker login --username AWS --password-stdin $ECR_URI

# Build the image (tag with git commit SHA — immutable reference)
IMAGE_TAG=$(git rev-parse --short HEAD)
docker build -t $ECR_URI:$IMAGE_TAG ./services/user-service

# Push
docker push $ECR_URI:$IMAGE_TAG
echo "Image pushed: $ECR_URI:$IMAGE_TAG"
```

### Step 2.4 — Store Secrets in Secrets Manager

```bash
# Database password (never type real passwords in bash history)
aws secretsmanager create-secret \
  --name "govplatform/dev/user-service/db-password" \
  --secret-string '{"password":"CHANGE_THIS_TO_REAL_PASSWORD"}' \
  --region eu-west-2 \
  --profile govplatform-dev

# Database connection string
aws secretsmanager create-secret \
  --name "govplatform/dev/user-service/db-url" \
  --secret-string "postgresql://userservice:CHANGE_THIS@$(terraform output -raw rds_endpoint)/userservice" \
  --region eu-west-2 \
  --profile govplatform-dev
```

**Lesson:** Notice we store the connection string in Secrets Manager, not in a Kubernetes ConfigMap or Helm values file. If those files get committed to Git by accident, the database is exposed. Secrets Manager with KMS encryption is the correct location.

### Step 2.5 — Create ExternalSecret (Kubernetes → Secrets Manager sync)

```yaml
# k8s/user-service/external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: user-service-secrets
  namespace: default
spec:
  refreshInterval: 1h       # re-sync every hour (picks up rotated secrets)
  secretStoreRef:
    name: aws-secretsmanager
    kind: ClusterSecretStore
  target:
    name: user-service-secrets   # creates a K8s Secret with this name
    creationPolicy: Owner
  data:
    - secretKey: DB_URL
      remoteRef:
        key: govplatform/dev/user-service/db-url
    - secretKey: DB_PASSWORD
      remoteRef:
        key: govplatform/dev/user-service/db-password
        property: password
```

```bash
kubectl apply -f k8s/user-service/external-secret.yaml

# Verify the Kubernetes Secret was created by ESO
kubectl get secret user-service-secrets -o yaml
# You should see base64-encoded values — they came from Secrets Manager
```

### Step 2.6 — Deploy to EKS

```bash
# Update the image tag in your deployment manifest
# (In the pipeline this happens automatically)
sed -i "s|IMAGE_TAG|$IMAGE_TAG|g" k8s/user-service/deployment.yaml

kubectl apply -f k8s/user-service/

# Watch the rollout
kubectl rollout status deployment/user-service
# Should output: "deployment.apps/user-service successfully rolled out"

# Check pods are running
kubectl get pods -l app=user-service
# Should show 2 pods in Running state

# Check the ALB was created
kubectl get ingress user-service-ingress
# Should show an ADDRESS (the ALB DNS name) within 2–3 minutes
```

### Step 2.7 — Test the Deployed Service

```bash
ALB_URL=$(kubectl get ingress user-service-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Service URL: https://$ALB_URL"

# Health check
curl https://$ALB_URL/health

# Create a user
curl -X POST https://$ALB_URL/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Olamide Kosile","email":"olamidekosile@gmail.com"}'
```

**If it fails:**
```bash
# Check pod logs
kubectl logs -l app=user-service --tail=50

# Check events (why did the pod fail to start?)
kubectl describe pod -l app=user-service

# Check if secrets were mounted correctly
kubectl exec -it $(kubectl get pod -l app=user-service -o name | head -1) -- env | grep DB
```

---

## PHASE 3: CI/CD Pipeline

### Step 3.1 — GitHub Actions Workflow

The workflow at `.github/workflows/ci.yml` triggers on every push and PR.

Push a test commit to verify it runs:
```bash
git add .
git commit -m "test: trigger pipeline"
git push origin main
```

Go to **GitHub → Actions** and watch the pipeline run. You should see:
- Lint and test job (green)
- Security scan job (green — or with findings logged but non-blocking)
- Build and push job (green)
- All in parallel — total time < 4 minutes

### Step 3.2 — Deploy AWS CodePipeline (CloudFormation)

```bash
# Deploy the pipeline stack
aws cloudformation deploy \
  --stack-name govplatform-pipeline \
  --template-file cicd/pipeline/pipeline.yml \
  --parameter-overrides \
    RepositoryName=FullAWSDevOpsProject \
    BranchName=main \
    ECRRepoName=govplatform/user-service \
    ECSClusterName=govplatform-dev \
    NotificationEmail=olamidekosile@gmail.com \
  --capabilities CAPABILITY_IAM \
  --region eu-west-2 \
  --profile govplatform-dev

# Check the pipeline was created
aws codepipeline get-pipeline-state \
  --name FullAWSDevOpsProject-pipeline \
  --region eu-west-2 \
  --profile govplatform-dev
```

### Step 3.3 — Trigger a Full Deployment

```bash
# Make a visible change
echo "# Deployment test $(date)" >> services/user-service/README.md
git add . && git commit -m "feat: deployment pipeline test"
git push origin main
```

Watch in the AWS console:
1. **CodePipeline** → see the pipeline run
2. **CodeBuild** → watch the build logs
3. **EKS** → `kubectl get pods -w` — watch new pods replace old ones

**Expected time:** 6–8 minutes from push to deployed.

---

## PHASE 4: Security Configuration

### Step 4.1 — Verify Security Services Are Running

```bash
# GuardDuty — should be enabled (Control Tower did this)
aws guardduty list-detectors --region eu-west-2 --profile govplatform-dev
# Should return a detectorId

# SecurityHub — enable if not already
aws securityhub enable-security-hub \
  --enable-default-standards \
  --region eu-west-2 \
  --profile govplatform-dev

# AWS Config — verify rules are active
aws configservice describe-config-rules --region eu-west-2 --profile govplatform-dev

# AWS Inspector v2
aws inspector2 enable \
  --resource-types "ECR" "LAMBDA" \
  --region eu-west-2 \
  --profile govplatform-dev
```

### Step 4.2 — Deploy AWS Config Custom Rules

```bash
aws cloudformation deploy \
  --stack-name govplatform-config-rules \
  --template-file security/config-rules/config-rules.yml \
  --capabilities CAPABILITY_IAM \
  --region eu-west-2 \
  --profile govplatform-dev
```

Check compliance:
```bash
aws configservice get-compliance-summary-by-config-rule \
  --region eu-west-2 \
  --profile govplatform-dev
```

### Step 4.3 — Deploy WAF

```bash
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `govplatform`)].LoadBalancerArn' \
  --output text \
  --region eu-west-2 \
  --profile govplatform-dev)

aws cloudformation deploy \
  --stack-name govplatform-waf \
  --template-file networking/waf/waf-webacl.yml \
  --parameter-overrides \
    ALBArn=$ALB_ARN \
    Environment=dev \
  --region eu-west-2 \
  --profile govplatform-dev
```

**Test WAF is working:**
```bash
# This should be BLOCKED by the geo restriction rule (using a VPN to simulate non-UK IP)
# Or test with a known bad user agent
curl -H "User-Agent: nikto" https://$ALB_URL/health
# Expected: 403 Forbidden
```

### Step 4.4 — Enable Macie for PII Detection

```bash
aws macie2 enable-macie --region eu-west-2 --profile govplatform-dev

# Create a classification job to scan S3 buckets
aws macie2 create-classification-job \
  --job-type ONE_TIME \
  --name "govplatform-initial-pii-scan" \
  --s3-job-definition '{
    "bucketDefinitions": [{
      "accountId": "'$ACCOUNT_ID'",
      "buckets": ["govplatform-documents-dev"]
    }]
  }' \
  --region eu-west-2 \
  --profile govplatform-dev
```

**Lesson:** Macie uses machine learning to detect PII (names, email addresses, national insurance numbers, credit card data) in S3 buckets. For DWP, this is critical — citizen data must never be stored unencrypted or in the wrong bucket.

---

## PHASE 5: Monitoring

### Step 5.1 — Enable Container Insights

```bash
aws eks update-cluster-config \
  --name govplatform-dev \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}' \
  --region eu-west-2 \
  --profile govplatform-dev

# Install CloudWatch agent for Container Insights
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-serviceaccount.yaml

kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-configmap.yaml

kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-daemonset.yaml
```

### Step 5.2 — Deploy CloudWatch Alarms

```bash
# Deploy the monitoring Terraform module
cd infrastructure/terraform
terraform apply -var-file=environments/dev.tfvars -target=module.monitoring
```

Verify alarms exist:
```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "govplatform" \
  --query 'MetricAlarms[*].[AlarmName,StateValue]' \
  --output table \
  --region eu-west-2 \
  --profile govplatform-dev
```

### Step 5.3 — Test Alerting

```bash
# Manually trigger an alarm to test SNS is working
aws cloudwatch set-alarm-state \
  --alarm-name "govplatform-dev-5xx-errors" \
  --state-value ALARM \
  --state-reason "Manual test" \
  --region eu-west-2 \
  --profile govplatform-dev

# You should receive an email within 60 seconds
# Reset the alarm
aws cloudwatch set-alarm-state \
  --alarm-name "govplatform-dev-5xx-errors" \
  --state-value OK \
  --state-reason "Test complete" \
  --region eu-west-2 \
  --profile govplatform-dev
```

### Step 5.4 — Access X-Ray Service Map

1. AWS Console → **X-Ray** → **Service Map**
2. You should see: `user-service` → `PostgreSQL (RDS)`
3. Hover over the user-service node to see request rate, latency, error rate
4. Click a trace to see the full request breakdown

**Lesson:** X-Ray traces are the single most useful tool for diagnosing latency problems. When a user says "the page is slow", the X-Ray trace will show exactly which downstream call is taking 2 seconds.

### Step 5.5 — Set Up Amazon Managed Grafana (Optional but Impressive)

```bash
# Create a Grafana workspace
aws grafana create-workspace \
  --workspace-name "govplatform-grafana" \
  --account-access-type CURRENT_ACCOUNT \
  --authentication-providers AWS_SSO \
  --permission-type SERVICE_MANAGED \
  --region eu-west-2 \
  --profile govplatform-dev

# After creation, add data sources via the console:
# 1. Amazon Managed Grafana workspace → Data sources → Add
# 2. Select CloudWatch → eu-west-2
# 3. Import dashboard ID 17665 (EKS Cluster Overview)
```

---

## PHASE 6: Chaos and Validation

> **Why this phase?** Any platform engineer worth their salary doesn't just build the happy path — they prove the system survives failure.

### Validate: Rolling Deployment Works

```bash
# Deploy a new version
kubectl set image deployment/user-service user-service=$ECR_URI:new-tag

# Watch it roll out without downtime
kubectl rollout status deployment/user-service

# Run continuous health checks during rollout
while true; do curl -s https://$ALB_URL/health | jq .status; sleep 1; done
# Should always return "healthy" — never a connection error
```

### Validate: Auto-Rollback on Failure

```bash
# Deploy a broken image tag (doesn't exist in ECR)
kubectl set image deployment/user-service user-service=$ECR_URI:broken-tag

# Kubernetes will try to pull the image — it fails — ImagePullBackOff
kubectl get pods -l app=user-service
# Should show: old pods still Running, new pods in ImagePullBackOff

# Rollback
kubectl rollout undo deployment/user-service

# Verify
kubectl get pods -l app=user-service
# Should show: all pods Running again
```

### Validate: Pod Autoscaling Works

```bash
# Install a load generator
kubectl run load-generator --image=busybox --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://user-service.default.svc.cluster.local/health; done"

# Watch HPA scale up
kubectl get hpa user-service -w
# TARGETS column should increase, then REPLICAS should go from 2 to more

# Stop the load
kubectl delete pod load-generator
# Watch it scale back down (takes ~5 min due to stabilisation window)
```

### Validate: Security Controls Are Enforced

```bash
# Test 1: Try to disable CloudTrail (should be blocked by SCP)
aws cloudtrail stop-logging \
  --name arn:aws:cloudtrail:eu-west-2:$ACCOUNT_ID:trail/aws-controltower-BaselineCloudTrail \
  --profile govplatform-dev
# Expected: An error occurred (AccessDeniedException)... SCP blocks this

# Test 2: Try to create an IAM user (should be blocked by SCP in prod)
# (only test this in dev — prod SCP would block it)

# Test 3: Try to create an unencrypted S3 bucket
aws s3api create-bucket \
  --bucket "govplatform-test-unencrypted-$(date +%s)" \
  --region eu-west-2 \
  --profile govplatform-dev
# This will succeed but Config rule will immediately flag it as NON_COMPLIANT
```

---

## Common Problems and Solutions

### Problem: `kubectl` returns "Unauthorized"
```bash
# Refresh your kubeconfig
aws eks update-kubeconfig --name govplatform-dev --region eu-west-2 --profile govplatform-dev
# If still failing: check that your IAM role is in the aws-auth ConfigMap
kubectl describe configmap aws-auth -n kube-system
```

### Problem: Pods stuck in "Pending"
```bash
kubectl describe pod <pod-name>
# Look at "Events" section
# Common causes:
# - "Insufficient CPU/memory" → cluster autoscaler hasn't scaled yet, wait 2 min
# - "0/2 nodes are available" → no nodes match the pod's requirements
# - "PersistentVolumeClaim not bound" → EBS CSI driver issue
```

### Problem: External Secrets not syncing
```bash
kubectl describe externalsecret user-service-secrets
# Look at "Status" section
# Common causes:
# - IRSA not configured correctly → check ServiceAccount annotation
# - Secret doesn't exist in Secrets Manager → check the secret name spelling
```

### Problem: ALB not created after applying Ingress
```bash
kubectl describe ingress user-service-ingress
# Check the annotations are correct (ingress.class: alb)
# Check AWS Load Balancer Controller pods are running:
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### Problem: GitHub Actions can't push to ECR
```bash
# Check the OIDC trust policy on the IAM role
aws iam get-role --role-name github-actions-role --profile govplatform-dev
# Verify the condition matches your GitHub org and repo exactly
```

---

## Cost Management

### Estimated monthly cost breakdown
| Service | Cost | Notes |
|---------|------|-------|
| EKS cluster | ~£70 | Control plane only |
| EC2 t3.medium × 2 (spot) | ~£20 | Spot saves ~70% vs on-demand |
| RDS db.t3.micro Multi-AZ | ~£35 | Cheapest Multi-AZ option |
| NAT Gateways × 3 | ~£100 | Biggest cost — reduce to 1 for dev |
| ALB × 2 | ~£18 | One per service group |
| CloudWatch | ~£15 | Logs + metrics + dashboards |
| Security services | ~£25 | GuardDuty + Config + Inspector |
| ECR, S3, SSM | ~£5 | Storage |
| **Total (3 NAT GW)** | **~£288/month** | |
| **Total (1 NAT GW)** | **~£215/month** | Dev-only cost saving |

### To minimise costs:
```bash
# Option 1: Reduce to 1 NAT Gateway for dev (not HA but cheaper)
# In environments/dev.tfvars:
# nat_gateway_count = 1  (add this variable)

# Option 2: Scale down EKS nodes outside working hours
# Create an EventBridge schedule to set desired count to 0 at 7pm, 2 at 8am
# (pods will be rescheduled when nodes come back)

# Option 3: Use t3.nano or t3.micro RDS in dev (not Multi-AZ)
# db_instance_class = "db.t3.micro"
# multi_az = false
```

---

## Cleanup (When Done Practising)

```bash
# 1. Delete Kubernetes resources first (otherwise ALBs/volumes are orphaned)
kubectl delete -f k8s/ --recursive

# 2. Destroy Terraform infrastructure
cd infrastructure/terraform
terraform destroy -var-file=environments/dev.tfvars
# Type 'yes' when prompted — this deletes everything

# 3. Empty and delete the state bucket manually (Terraform can't delete non-empty buckets)
aws s3 rm s3://govplatform-terraform-state-$ACCOUNT_ID --recursive --profile govplatform-dev
aws s3api delete-bucket --bucket govplatform-terraform-state-$ACCOUNT_ID --profile govplatform-dev

# 4. Optionally close the govplatform-dev account in Control Tower
# Control Tower → Account Factory → Unmanage (or use Organizations to close)
```

> **Important:** Closing an AWS account takes 90 days for permanent closure. Until then, you are billed for any remaining resources.
