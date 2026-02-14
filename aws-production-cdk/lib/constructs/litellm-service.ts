import { Duration } from 'aws-cdk-lib';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as servicediscovery from 'aws-cdk-lib/aws-servicediscovery';
import { Construct } from 'constructs';
import { EnvironmentConfig } from '../config/environment.js';

export interface LiteLLMServiceProps {
  config: EnvironmentConfig;
  cluster: ecs.ICluster;
  vpc: ec2.IVpc;
  listener: elbv2.IApplicationListener;
  executionRole: iam.IRole;
  taskRole: iam.IRole;
  securityGroup: ec2.ISecurityGroup;
  namespace: servicediscovery.IPrivateDnsNamespace;
  secrets: Record<string, secretsmanager.ISecret>;
}

/**
 * LiteLLMService encapsulates the LiteLLM AI gateway ECS service:
 * Fargate task definition, ALB listener rules, and CloudMap entry.
 *
 * LiteLLM proxies AI model requests to AWS Bedrock (primary, via IAM task role)
 * and Anthropic API (fallback). It also integrates with Langfuse for
 * observability and enforces guardrails/enforcement hooks server-side.
 */
export class LiteLLMService extends Construct {
  public readonly service: ecs.FargateService;
  public readonly targetGroup: elbv2.ApplicationTargetGroup;

  constructor(scope: Construct, id: string, props: LiteLLMServiceProps) {
    super(scope, id);

    const { config } = props;

    // Derive baseDomain: 'coder.company.com' -> 'company.com'
    const domainParts = config.domain.split('.');
    const baseDomain =
      domainParts.length > 2
        ? domainParts.slice(1).join('.')
        : config.domain;

    // -----------------------------------------------------------------
    // Fargate Task Definition
    // -----------------------------------------------------------------
    const taskDefinition = new ecs.FargateTaskDefinition(
      this,
      'TaskDefinition',
      {
        family: 'litellm',
        cpu: 512,
        memoryLimitMiB: 2048,
        taskRole: props.taskRole,
        executionRole: props.executionRole,
      },
    );

    // -----------------------------------------------------------------
    // Container
    // -----------------------------------------------------------------
    // TODO: config.yaml mounting — Fargate cannot mount local files.
    // Options for production:
    //   1. Bake config.yaml into a custom Docker image (preferred)
    //   2. Store on EFS and mount as a volume
    //   3. Fetch from S3 in an entrypoint script
    // For now the command references /app/config.yaml which must be
    // present in the container image.
    taskDefinition.addContainer('litellm', {
      image: ecs.ContainerImage.fromRegistry(config.litellmImage),
      command: ['--config', '/app/config.yaml', '--port', '4000'],
      portMappings: [{ containerPort: 4000, protocol: ecs.Protocol.TCP }],
      environment: {
        AWS_REGION_NAME: config.region,
        DEFAULT_ENFORCEMENT_LEVEL: 'standard',
        GUARDRAILS_ENABLED: 'true',
        DEFAULT_GUARDRAIL_LEVEL: 'standard',
        LANGFUSE_HOST: 'http://langfuse-web.coder-production.local:3000',
        LITELLM_ANTHROPIC_DISABLE_URL_SUFFIX: 'true',
        CUSTOM_LLM_API_BASE: config.customLlmApiBase,
        CUSTOM_LLM_CLAUDE_API_BASE: `${config.customLlmApiBase}/claude/messages`,
      },
      secrets: {
        DATABASE_URL: ecs.Secret.fromSecretsManager(
          props.secrets['litellm/database'],
        ),
        LITELLM_MASTER_KEY: ecs.Secret.fromSecretsManager(
          props.secrets['litellm/master-key'],
        ),
        ANTHROPIC_API_KEY: ecs.Secret.fromSecretsManager(
          props.secrets['litellm/anthropic-api-key'],
        ),
        CUSTOM_LLM_API_KEY: ecs.Secret.fromSecretsManager(
          props.secrets['custom-llm/api-key'],
        ),
        LANGFUSE_PUBLIC_KEY: ecs.Secret.fromSecretsManager(
          props.secrets['langfuse/api-keys'],
          'public_key',
        ),
        LANGFUSE_SECRET_KEY: ecs.Secret.fromSecretsManager(
          props.secrets['langfuse/api-keys'],
          'secret_key',
        ),
      },
      logging: ecs.LogDrivers.awsLogs({ streamPrefix: 'litellm' }),
      healthCheck: {
        command: [
          'CMD-SHELL',
          'python3 -c "import urllib.request; urllib.request.urlopen(\'http://localhost:4000/health/readiness\')"',
        ],
        interval: Duration.seconds(30),
        timeout: Duration.seconds(10),
        retries: 3,
        startPeriod: Duration.seconds(30),
      },
    });

    // -----------------------------------------------------------------
    // Fargate Service
    // -----------------------------------------------------------------
    this.service = new ecs.FargateService(this, 'Service', {
      cluster: props.cluster,
      taskDefinition,
      desiredCount: 2,
      securityGroups: [props.securityGroup],
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      capacityProviderStrategies: [
        { capacityProvider: 'FARGATE', weight: 1 },
      ],
      cloudMapOptions: {
        cloudMapNamespace: props.namespace,
        name: 'litellm',
      },
      circuitBreaker: { enable: true, rollback: true },
    });

    // -----------------------------------------------------------------
    // ALB Target Group
    // -----------------------------------------------------------------
    this.targetGroup = new elbv2.ApplicationTargetGroup(this, 'TargetGroup', {
      port: 4000,
      protocol: elbv2.ApplicationProtocol.HTTP,
      vpc: props.vpc,
      targets: [this.service],
      healthCheck: {
        path: '/health/readiness',
        interval: Duration.seconds(30),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
      deregistrationDelay: Duration.seconds(30),
    });

    // -----------------------------------------------------------------
    // ALB Listener Rule
    // -----------------------------------------------------------------
    new elbv2.ApplicationListenerRule(this, 'LitellmHostRule', {
      listener: props.listener,
      priority: 400,
      conditions: [elbv2.ListenerCondition.hostHeaders([`ai.${baseDomain}`])],
      action: elbv2.ListenerAction.forward([this.targetGroup]),
    });
  }
}
