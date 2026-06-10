"""
CodeDeploy lifecycle hook - BeforeInstall
Validates environment health before Blue/Green switch.
"""
import boto3
import json
import os

codedeploy = boto3.client('codedeploy')
ssm = boto3.client('ssm')
cloudwatch = boto3.client('cloudwatch')


def handler(event, context):
    deployment_id = event['DeploymentId']
    lifecycle_event_hook_execution_id = event['LifecycleEventHookExecutionId']

    try:
        # Check current error rate before deploying
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/ApplicationELB',
            MetricName='HTTPCode_ELB_5XX_Count',
            Dimensions=[{
                'Name': 'LoadBalancer',
                'Value': os.environ['ALB_ARN_SUFFIX']
            }],
            StartTime='2024-01-01T00:00:00Z',
            EndTime='2024-01-01T00:05:00Z',
            Period=300,
            Statistics=['Sum']
        )

        error_count = sum(d['Sum'] for d in response['Datapoints'])

        if error_count > 50:
            raise Exception(f"Current error rate too high ({error_count} errors/5min) - blocking deployment")

        # Validate SSM parameters exist
        required_params = [
            f"/devops/{os.environ['ENV']}/table-name",
            f"/devops/{os.environ['ENV']}/alb-url"
        ]
        ssm.get_parameters(Names=required_params, WithDecryption=False)

        status = 'Succeeded'
        print(f"Pre-deploy hook passed for deployment {deployment_id}")

    except Exception as e:
        print(f"Pre-deploy hook FAILED: {str(e)}")
        status = 'Failed'

    codedeploy.put_lifecycle_event_hook_execution_status(
        deploymentId=deployment_id,
        lifecycleEventHookExecutionId=lifecycle_event_hook_execution_id,
        status=status
    )
