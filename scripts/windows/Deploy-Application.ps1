# Deploy-Application.ps1
# PowerShell deployment script - demonstrates Windows scripting for interview
# Usage: .\Deploy-Application.ps1 -Environment dev -ImageTag abc123
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('dev','staging','prod')]
    [string]$Environment,
    [Parameter(Mandatory)][string]$ImageTag,
    [string]$Region = 'eu-west-2',
    [string]$AppName = 'full-aws-devops-app'
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $color = if ($Level -eq 'ERROR') { 'Red' } elseif ($Level -eq 'WARN') { 'Yellow' } else { 'Green' }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

Write-Log "Starting deployment of $AppName`:$ImageTag to $Environment"

# Production safeguard
if ($Environment -eq 'prod') {
    $confirm = Read-Host "Deploying to PRODUCTION. Type 'yes' to confirm"
    if ($confirm -ne 'yes') { throw "Deployment aborted by user" }
}

# Get AWS account ID
$accountId = (aws sts get-caller-identity --query Account --output text)
$ecrUri = "$accountId.dkr.ecr.$Region.amazonaws.com/$AppName"

# Verify image exists
Write-Log "Verifying image $ImageTag in ECR..."
$imageCheck = aws ecr describe-images `
    --repository-name $AppName `
    --image-ids "imageTag=$ImageTag" `
    --region $Region 2>&1
if ($LASTEXITCODE -ne 0) { throw "Image $ImageTag not found in ECR: $imageCheck" }

# Get current task definition
Write-Log "Fetching current ECS task definition..."
$taskFamily = "$AppName-$Environment"
$currentTask = aws ecs describe-task-definition `
    --task-definition $taskFamily `
    --query 'taskDefinition' `
    --output json `
    --region $Region | ConvertFrom-Json

# Update image URI
$currentTask.containerDefinitions[0].image = "${ecrUri}:${ImageTag}"

# Remove read-only fields
$fieldsToRemove = @('taskDefinitionArn','revision','status','requiresAttributes','compatibilities','registeredAt','registeredBy')
$taskJson = $currentTask | Select-Object -ExcludeProperty $fieldsToRemove | ConvertTo-Json -Depth 20

# Register new task definition
Write-Log "Registering new task definition..."
$newTaskDef = aws ecs register-task-definition `
    --cli-input-json $taskJson `
    --query 'taskDefinition.taskDefinitionArn' `
    --output text `
    --region $Region
Write-Log "New task definition ARN: $newTaskDef"

# Update ECS service
Write-Log "Updating ECS service..."
$cluster = aws ssm get-parameter `
    --name "/devops/$Environment/ecs-cluster" `
    --query 'Parameter.Value' `
    --output text `
    --region $Region

aws ecs update-service `
    --cluster $cluster `
    --service "$AppName-$Environment" `
    --task-definition $newTaskDef `
    --region $Region | Out-Null

Write-Log "Deployment initiated. Monitoring rollout..."

# Wait for service stability
$maxWait = 600
$elapsed = 0
do {
    Start-Sleep -Seconds 15
    $elapsed += 15

    $deployments = aws ecs describe-services `
        --cluster $cluster `
        --services "$AppName-$Environment" `
        --query 'services[0].deployments' `
        --output json `
        --region $Region | ConvertFrom-Json

    $primary = $deployments | Where-Object { $_.status -eq 'PRIMARY' }
    Write-Log "Running: $($primary.runningCount)/$($primary.desiredCount) tasks ($elapsed`s elapsed)"

    if ($primary.runningCount -eq $primary.desiredCount -and $deployments.Count -eq 1) {
        Write-Log "Deployment SUCCEEDED - all tasks healthy" -Level INFO
        exit 0
    }

    if ($primary.rolloutStateReason -match 'failed') {
        throw "Deployment FAILED: $($primary.rolloutStateReason)"
    }

} while ($elapsed -lt $maxWait)

throw "Deployment timed out after ${maxWait}s"
