#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { PipelineStack } from '../lib/pipeline-stack';

const app = new cdk.App();

const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION ?? 'eu-west-2',
};

new PipelineStack(app, 'FullAWSDevOpsPipeline', {
  env,
  environment: 'prod',
  repoName: 'full-aws-devops-app',
  approvalEmail: process.env.APPROVAL_EMAIL ?? 'devops@example.com',
  tags: {
    Project: 'FullAWSDevOps',
    ManagedBy: 'CDK',
  },
});

app.synth();
