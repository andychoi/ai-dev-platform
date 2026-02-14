import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import { Construct } from 'constructs';
import { EnvironmentConfig } from '../config/environment.js';
import { NetworkStackOutputs } from './network-stack.js';
import { DataStackOutputs } from './data-stack.js';
import { CoderService } from '../constructs/coder-service.js';

export interface PlatformStackProps extends cdk.StackProps {
  config: EnvironmentConfig;
  network: NetworkStackOutputs;
  data: DataStackOutputs;
}

export interface PlatformStackOutputs {
  cluster: ecs.ICluster;
  alb: elbv2.IApplicationLoadBalancer;
  listener: elbv2.IApplicationListener;
  executionRole: iam.IRole;
  taskRoles: {
    coder: iam.IRole;
    litellm: iam.IRole;
    keyProvisioner: iam.IRole;
    langfuse: iam.IRole;
    workspace: iam.IRole;
  };
}

export class PlatformStack extends cdk.Stack {
  public readonly outputs: PlatformStackOutputs;

  constructor(scope: Construct, id: string, props: PlatformStackProps) {
    super(scope, id, props);

    const { config, network, data } = props;

    // Apply tags to all resources in this stack
    for (const [key, value] of Object.entries(config.tags)) {
      cdk.Tags.of(this).add(key, value);
    }

    // ---------------------------------------------------------------
    // ECS Cluster
    // ---------------------------------------------------------------
    const cluster = new ecs.Cluster(this, 'Cluster', {
      vpc: network.vpc,
      containerInsights: true,
      enableFargateCapacityProviders: true,
    });

    // ---------------------------------------------------------------
    // ACM Certificate
    // ---------------------------------------------------------------
    // Extract the base domain for SAN (e.g., 'coder.company.com' -> '*.company.com')
    const domainParts = config.domain.split('.');
    const baseDomain =
      domainParts.length > 2
        ? domainParts.slice(1).join('.')
        : config.domain;

    const certificate = new acm.Certificate(this, 'Certificate', {
      domainName: config.domain,
      subjectAlternativeNames: [`*.${baseDomain}`],
      validation: acm.CertificateValidation.fromDns(),
    });

    // ---------------------------------------------------------------
    // Internal ALB
    // ---------------------------------------------------------------
    const alb = new elbv2.ApplicationLoadBalancer(this, 'Alb', {
      vpc: network.vpc,
      internetFacing: false,
      securityGroup: network.securityGroups.alb,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
    });

    const listener = alb.addListener('HttpsListener', {
      port: 443,
      protocol: elbv2.ApplicationProtocol.HTTPS,
      certificates: [certificate],
      defaultAction: elbv2.ListenerAction.fixedResponse(404, {
        contentType: 'text/plain',
        messageBody: 'Not Found',
      }),
    });

    // ---------------------------------------------------------------
    // IAM Roles
    // ---------------------------------------------------------------
    const ecsTaskAssumePolicy = new iam.ServicePrincipal(
      'ecs-tasks.amazonaws.com',
    );

    // Shared Execution Role
    const executionRole = new iam.Role(this, 'ExecutionRole', {
      assumedBy: ecsTaskAssumePolicy,
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName(
          'service-role/AmazonECSTaskExecutionRolePolicy',
        ),
      ],
    });
    executionRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'secretsmanager:GetSecretValue',
          'secretsmanager:DescribeSecret',
        ],
        resources: [
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:prod/*`,
        ],
      }),
    );
    executionRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'logs:CreateLogGroup',
          'logs:CreateLogStream',
          'logs:PutLogEvents',
        ],
        resources: ['*'],
      }),
    );

    // Coder Task Role
    const coderTaskRole = new iam.Role(this, 'CoderTaskRole', {
      assumedBy: ecsTaskAssumePolicy,
    });
    coderTaskRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'secretsmanager:GetSecretValue',
          'secretsmanager:DescribeSecret',
        ],
        resources: [
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:prod/coder/*`,
        ],
      }),
    );
    coderTaskRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['s3:GetObject', 's3:PutObject', 's3:ListBucket'],
        resources: [
          data.buckets.terraformState.bucketArn,
          `${data.buckets.terraformState.bucketArn}/*`,
        ],
      }),
    );
    coderTaskRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'ecs:RunTask',
          'ecs:DescribeTaskDefinition',
          'ecs:DescribeTasks',
          'ecs:StopTask',
        ],
        resources: ['*'],
      }),
    );
    coderTaskRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'elasticfilesystem:CreateAccessPoint',
          'elasticfilesystem:DescribeAccessPoints',
          'elasticfilesystem:DeleteAccessPoint',
        ],
        resources: [data.fileSystem.fileSystemArn],
      }),
    );

    // LiteLLM Task Role
    const litellmTaskRole = new iam.Role(this, 'LitellmTaskRole', {
      assumedBy: ecsTaskAssumePolicy,
    });
    litellmTaskRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['bedrock:InvokeModel', 'bedrock:InvokeModelWithResponseStream'],
        resources: ['*'],
      }),
    );
    litellmTaskRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'secretsmanager:GetSecretValue',
          'secretsmanager:DescribeSecret',
        ],
        resources: [
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:prod/litellm/*`,
        ],
      }),
    );

    // Key Provisioner Task Role
    const keyProvisionerTaskRole = new iam.Role(
      this,
      'KeyProvisionerTaskRole',
      {
        assumedBy: ecsTaskAssumePolicy,
      },
    );
    keyProvisionerTaskRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'secretsmanager:GetSecretValue',
          'secretsmanager:DescribeSecret',
        ],
        resources: [
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:prod/key-provisioner/*`,
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:prod/litellm/master-key*`,
        ],
      }),
    );

    // Langfuse Task Role
    const langfuseTaskRole = new iam.Role(this, 'LangfuseTaskRole', {
      assumedBy: ecsTaskAssumePolicy,
    });
    langfuseTaskRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'secretsmanager:GetSecretValue',
          'secretsmanager:DescribeSecret',
        ],
        resources: [
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:prod/langfuse/*`,
        ],
      }),
    );
    langfuseTaskRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['s3:GetObject', 's3:PutObject', 's3:ListBucket'],
        resources: [
          data.buckets.langfuseEvents.bucketArn,
          `${data.buckets.langfuseEvents.bucketArn}/*`,
          data.buckets.langfuseMedia.bucketArn,
          `${data.buckets.langfuseMedia.bucketArn}/*`,
        ],
      }),
    );

    // Workspace Task Role
    const workspaceTaskRole = new iam.Role(this, 'WorkspaceTaskRole', {
      assumedBy: ecsTaskAssumePolicy,
    });
    workspaceTaskRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'logs:CreateLogGroup',
          'logs:CreateLogStream',
          'logs:PutLogEvents',
        ],
        resources: ['*'],
      }),
    );

    // Allow Coder to pass the workspace task role to workspace tasks
    coderTaskRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['iam:PassRole'],
        resources: [
          workspaceTaskRole.roleArn,
          executionRole.roleArn,
        ],
      }),
    );

    // ---------------------------------------------------------------
    // SSM Parameters (CDK -> Terraform bridge)
    // ---------------------------------------------------------------
    const ssmPrefix = '/coder-production';

    new ssm.StringParameter(this, 'ParamClusterArn', {
      parameterName: `${ssmPrefix}/cluster-arn`,
      stringValue: cluster.clusterArn,
    });

    new ssm.StringParameter(this, 'ParamClusterName', {
      parameterName: `${ssmPrefix}/cluster-name`,
      stringValue: cluster.clusterName,
    });

    new ssm.StringParameter(this, 'ParamExecutionRoleArn', {
      parameterName: `${ssmPrefix}/task-execution-role-arn`,
      stringValue: executionRole.roleArn,
    });

    new ssm.StringParameter(this, 'ParamWorkspaceTaskRoleArn', {
      parameterName: `${ssmPrefix}/workspace-task-role-arn`,
      stringValue: workspaceTaskRole.roleArn,
    });

    new ssm.StringParameter(this, 'ParamWorkspaceSgId', {
      parameterName: `${ssmPrefix}/workspace-sg-id`,
      stringValue: network.securityGroups.ecsWorkspaces.securityGroupId,
    });

    const privateSubnetIds = network.vpc
      .selectSubnets({ subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS })
      .subnetIds.join(',');

    new ssm.StringParameter(this, 'ParamPrivateSubnetIds', {
      parameterName: `${ssmPrefix}/private-subnet-ids`,
      stringValue: privateSubnetIds,
    });

    new ssm.StringParameter(this, 'ParamEfsId', {
      parameterName: `${ssmPrefix}/efs-id`,
      stringValue: data.fileSystem.fileSystemId,
    });

    new ssm.StringParameter(this, 'ParamAlbListenerArn', {
      parameterName: `${ssmPrefix}/alb-listener-arn`,
      stringValue: listener.listenerArn,
    });

    // ---------------------------------------------------------------
    // Service Constructs
    // ---------------------------------------------------------------
    new CoderService(this, 'CoderService', {
      config,
      cluster,
      vpc: network.vpc,
      listener,
      executionRole,
      taskRole: coderTaskRole,
      securityGroup: network.securityGroups.ecsServices,
      fileSystem: data.fileSystem,
      namespace: network.namespace,
      secrets: data.secrets,
      databaseSecret: data.database.secret,
    });

    // ---------------------------------------------------------------
    // Stack outputs
    // ---------------------------------------------------------------
    this.outputs = {
      cluster,
      alb,
      listener,
      executionRole,
      taskRoles: {
        coder: coderTaskRole,
        litellm: litellmTaskRole,
        keyProvisioner: keyProvisionerTaskRole,
        langfuse: langfuseTaskRole,
        workspace: workspaceTaskRole,
      },
    };
  }
}
