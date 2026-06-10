# Operational Runbook

## Incident Response Playbooks

### P1: Service Down (5xx > 50%)

1. Check ALB target group health: `aws elbv2 describe-target-health --target-group-arn <arn>`
2. Check ECS service events: `aws ecs describe-services --cluster <c> --services <s>`
3. Check CloudWatch alarms: `aws cloudwatch describe-alarms --state-value ALARM`
4. If new deployment caused issue → rollback:
   ```bash
   aws deploy stop-deployment --deployment-id <id> --auto-rollback-enabled
   ```
5. Check X-Ray service map for downstream failures
6. Check CloudWatch Logs Insights: run `Top 10 Error Messages` query

### P2: High Latency (P99 > 2s)

1. Check X-Ray traces for slow segments
2. Check DynamoDB consumed capacity: CloudWatch `ConsumedReadCapacityUnits`
3. Check if auto-scaling has triggered: ECS desired count vs running count
4. Check NAT Gateway bandwidth (outbound calls slow)
5. Consider enabling DAX for DynamoDB if read-heavy

### P3: Deployment Stuck

1. Check CodeDeploy deployment status:
   ```bash
   aws deploy get-deployment --deployment-id <id>
   ```
2. Check Lambda hook logs: `/aws/lambda/devops-smoke-test-hook-<env>`
3. If stuck in traffic shift: manually stop and rollback
4. Check ECS task stopped reason:
   ```bash
   aws ecs describe-tasks --cluster <c> --tasks <task-id>
   ```

### Security Incident: GuardDuty Finding

1. Check Security Hub findings dashboard
2. If `UnauthorizedAccess:IAMUser/MaliciousIPCaller`:
   - Immediately disable IAM user: `aws iam update-user --user-name <u>`
   - Rotate all access keys
   - Review CloudTrail for actions taken
3. If `Recon:EC2/PortProbeUnprotectedPort`:
   - Review security group rules
   - Check WAF for attack pattern
4. Escalate to Security team within 30 minutes of P1 finding

## Regular Operations

### Rotating Database Password
```bash
./scripts/linux/rotate-secrets.sh arn:aws:secretsmanager:eu-west-2:ACCOUNT:secret:devops/prod/db-password
```

### Force ECS Redeployment
```bash
aws ecs update-service --cluster prod-cluster --service app-prod --force-new-deployment
```

### Check Pipeline Status
```bash
aws codepipeline get-pipeline-state --name full-aws-devops-app-pipeline
```

### Scaling ECS manually
```bash
aws ecs update-service --cluster prod-cluster --service app-prod --desired-count 4
```
