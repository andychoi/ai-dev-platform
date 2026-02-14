import { Duration } from 'aws-cdk-lib';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as servicediscovery from 'aws-cdk-lib/aws-servicediscovery';
import { Construct } from 'constructs';
import { EnvironmentConfig } from '../config/environment.js';

export interface KeyProvisionerServiceProps {
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
 * KeyProvisionerService encapsulates the key-provisioner microservice:
 * Fargate task definition, ALB listener rules, and CloudMap entry.
 *
 * The key-provisioner isolates the LiteLLM master key from workspace
 * containers. Workspaces authenticate with PROVISIONER_SECRET and receive
 * scoped virtual keys — they never see the master key.
 *
 * Image is built from shared/key-provisioner in this repository.
 */
export class KeyProvisionerService extends Construct {
  public readonly service: ecs.FargateService;
  public readonly targetGroup: elbv2.ApplicationTargetGroup;

  constructor(
    scope: Construct,
    id: string,
    props: KeyProvisionerServiceProps,
  ) {
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
        family: 'key-provisioner',
        cpu: 256,
        memoryLimitMiB: 512,
        taskRole: props.taskRole,
        executionRole: props.executionRole,
      },
    );

    // -----------------------------------------------------------------
    // Container
    // -----------------------------------------------------------------
    // Image is built from shared/key-provisioner in this repository.
    // config.keyProvisionerImage may be empty during initial setup;
    // a placeholder is used until the image is pushed to ECR.
    taskDefinition.addContainer('key-provisioner', {
      image: ecs.ContainerImage.fromRegistry(
        config.keyProvisionerImage || 'placeholder',
      ),
      portMappings: [{ containerPort: 8100, protocol: ecs.Protocol.TCP }],
      environment: {
        LITELLM_URL: 'http://litellm.coder-production.local:4000',
        CODER_URL: `https://coder.${baseDomain}`,
        PORT: '8100',
      },
      secrets: {
        LITELLM_MASTER_KEY: ecs.Secret.fromSecretsManager(
          props.secrets['litellm/master-key'],
        ),
        PROVISIONER_SECRET: ecs.Secret.fromSecretsManager(
          props.secrets['key-provisioner/secret'],
        ),
      },
      logging: ecs.LogDrivers.awsLogs({ streamPrefix: 'key-provisioner' }),
      healthCheck: {
        command: [
          'CMD-SHELL',
          'curl -f http://localhost:8100/health || exit 1',
        ],
        interval: Duration.seconds(30),
        timeout: Duration.seconds(5),
        retries: 3,
        startPeriod: Duration.seconds(15),
      },
    });

    // -----------------------------------------------------------------
    // Fargate Service
    // -----------------------------------------------------------------
    this.service = new ecs.FargateService(this, 'Service', {
      cluster: props.cluster,
      taskDefinition,
      desiredCount: 1,
      securityGroups: [props.securityGroup],
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      capacityProviderStrategies: [
        { capacityProvider: 'FARGATE', weight: 1 },
      ],
      cloudMapOptions: {
        cloudMapNamespace: props.namespace,
        name: 'key-provisioner',
      },
      circuitBreaker: { enable: true, rollback: true },
    });

    // -----------------------------------------------------------------
    // ALB Target Group
    // -----------------------------------------------------------------
    this.targetGroup = new elbv2.ApplicationTargetGroup(this, 'TargetGroup', {
      port: 8100,
      protocol: elbv2.ApplicationProtocol.HTTP,
      vpc: props.vpc,
      targets: [this.service],
      healthCheck: {
        path: '/health',
        interval: Duration.seconds(30),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
      deregistrationDelay: Duration.seconds(30),
    });

    // -----------------------------------------------------------------
    // ALB Listener Rule
    // -----------------------------------------------------------------
    // TODO: Add OIDC authenticate action before the forward action
    // for production use (Azure AD). This requires Azure AD client ID
    // and secret from Secrets Manager and the OIDC endpoints from config.
    new elbv2.ApplicationListenerRule(this, 'AdminHostRule', {
      listener: props.listener,
      priority: 200,
      conditions: [
        elbv2.ListenerCondition.hostHeaders([`admin.${baseDomain}`]),
      ],
      action: elbv2.ListenerAction.forward([this.targetGroup]),
    });
  }
}
