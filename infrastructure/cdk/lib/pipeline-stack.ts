import * as cdk from 'aws-cdk-lib';
import * as codecommit from 'aws-cdk-lib/aws-codecommit';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';
import * as codepipeline from 'aws-cdk-lib/aws-codepipeline';
import * as codepipeline_actions from 'aws-cdk-lib/aws-codepipeline-actions';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import { Construct } from 'constructs';

interface PipelineStackProps extends cdk.StackProps {
  environment: string;
  repoName: string;
  approvalEmail: string;
}

export class PipelineStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: PipelineStackProps) {
    super(scope, id, props);

    // KMS key for all pipeline artifacts
    const pipelineKey = new kms.Key(this, 'PipelineKey', {
      enableKeyRotation: true,
      description: 'CDK Pipeline artifact encryption key',
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Encrypted artifact bucket
    const artifactBucket = new s3.Bucket(this, 'ArtifactBucket', {
      encryptionKey: pipelineKey,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [{
        expiration: cdk.Duration.days(30),
      }],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // ECR Repository - immutable tags, scan on push
    const ecrRepo = new ecr.Repository(this, 'ECRRepo', {
      repositoryName: props.repoName,
      imageTagMutability: ecr.TagMutability.IMMUTABLE,
      imageScanOnPush: true,
      encryption: ecr.RepositoryEncryption.KMS,
      lifecycleRules: [{
        maxImageCount: 20,
        tagPrefixList: ['release-'],
        description: 'Keep last 20 release images',
      }],
    });

    // CodeCommit source
    const repo = codecommit.Repository.fromRepositoryName(
      this, 'Repo', props.repoName
    );

    // Build project
    const buildProject = new codebuild.PipelineProject(this, 'BuildProject', {
      projectName: `${props.repoName}-build`,
      buildSpec: codebuild.BuildSpec.fromSourceFilename('cicd/buildspec/buildspec-build.yml'),
      environment: {
        buildImage: codebuild.LinuxBuildImage.STANDARD_7_0,
        computeType: codebuild.ComputeType.MEDIUM,
        privileged: true,
        environmentVariables: {
          ECR_REPO_URI: { value: ecrRepo.repositoryUri },
          ECR_REPO_NAME: { value: props.repoName },
        },
      },
      encryptionKey: pipelineKey,
      logging: {
        cloudWatch: {
          logGroup: new cdk.aws_logs.LogGroup(this, 'BuildLogGroup', {
            logGroupName: `/codebuild/${props.repoName}-build`,
            retention: cdk.aws_logs.RetentionDays.ONE_MONTH,
          }),
        },
      },
    });

    // Grant ECR push permissions
    ecrRepo.grantPullPush(buildProject);
    buildProject.addToRolePolicy(new iam.PolicyStatement({
      actions: ['ecr:GetAuthorizationToken'],
      resources: ['*'],
    }));

    // SNS topic for approvals
    const approvalTopic = new sns.Topic(this, 'ApprovalTopic', {
      displayName: `${props.repoName} Production Approval`,
      masterKey: pipelineKey,
    });
    new sns.Subscription(this, 'ApprovalSubscription', {
      topic: approvalTopic,
      protocol: sns.SubscriptionProtocol.EMAIL,
      endpoint: props.approvalEmail,
    });

    // Pipeline artifacts
    const sourceArtifact = new codepipeline.Artifact('Source');
    const buildArtifact = new codepipeline.Artifact('Build');

    // CodePipeline
    const pipeline = new codepipeline.Pipeline(this, 'Pipeline', {
      pipelineName: `${props.repoName}-cdk-pipeline`,
      artifactBucket,
      enableKeyRotation: true,
      stages: [
        {
          stageName: 'Source',
          actions: [
            new codepipeline_actions.CodeCommitSourceAction({
              actionName: 'CodeCommit',
              repository: repo,
              branch: 'main',
              output: sourceArtifact,
              trigger: codepipeline_actions.CodeCommitTrigger.EVENTS,
            }),
          ],
        },
        {
          stageName: 'Build',
          actions: [
            new codepipeline_actions.CodeBuildAction({
              actionName: 'BuildAndTest',
              project: buildProject,
              input: sourceArtifact,
              outputs: [buildArtifact],
            }),
          ],
        },
        {
          stageName: 'ApproveProduction',
          actions: [
            new codepipeline_actions.ManualApprovalAction({
              actionName: 'ApproveForProduction',
              notificationTopic: approvalTopic,
              additionalInformation: 'Review build artifacts and approve for production',
            }),
          ],
        },
        {
          stageName: 'DeployProduction',
          actions: [
            new codepipeline_actions.EcsDeployAction({
              actionName: 'DeployToECS',
              service: ecs.FargateService.fromFargateServiceAttributes(this, 'ProdService', {
                serviceArn: cdk.Fn.importValue(`prod-ecs-service-arn`),
                cluster: ecs.Cluster.fromClusterArn(this, 'ProdCluster',
                  cdk.Fn.importValue(`prod-ecs-cluster-arn`)),
              }),
              input: buildArtifact,
            }),
          ],
        },
      ],
    });

    // Outputs
    new cdk.CfnOutput(this, 'PipelineArn', { value: pipeline.pipelineArn });
    new cdk.CfnOutput(this, 'ECRRepoUri', { value: ecrRepo.repositoryUri });
  }
}
