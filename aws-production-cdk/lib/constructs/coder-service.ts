import { Duration } from 'aws-cdk-lib';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as efs from 'aws-cdk-lib/aws-efs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as servicediscovery from 'aws-cdk-lib/aws-servicediscovery';
import { Construct } from 'constructs';
import { EnvironmentConfig } from '../config/environment.js';

export interface CoderServiceProps {
  config: EnvironmentConfig;
  cluster: ecs.ICluster;
  vpc: ec2.IVpc;
  listener: elbv2.IApplicationListener;
  executionRole: iam.IRole;
  taskRole: iam.IRole;
  securityGroup: ec2.ISecurityGroup;
  fileSystem: efs.IFileSystem;
  namespace: servicediscovery.IPrivateDnsNamespace;
  /** Manually-created secrets from DataStack (keyed by logical name). */
  secrets: Record<string, secretsmanager.ISecret>;
  /** RDS auto-generated credentials secret (for CODER_PG_CONNECTION_URL). */
  databaseSecret: secretsmanager.ISecret;
}

/**
 * CoderService encapsulates the Coder management-plane ECS service:
 * Fargate task definition, EFS mount, ALB listener rules, and CloudMap entry.
 */
export class CoderService extends Construct {
  public readonly service: ecs.FargateService;
  public readonly targetGroup: elbv2.ApplicationTargetGroup;

  constructor(scope: Construct, id: string, props: CoderServiceProps) {
    super(scope, id);

    const { config } = props;

    // Derive baseDomain: 'coder.company.com' -> 'company.com'
    const domainParts = config.domain.split('.');
    const baseDomain =
      domainParts.length > 2
        ? domainParts.slice(1).join('.')
        : config.domain;

    // -----------------------------------------------------------------
    // EFS Access Point
    // -----------------------------------------------------------------
    const accessPoint = new efs.AccessPoint(this, 'CoderDataAccessPoint', {
      fileSystem: props.fileSystem,
      path: '/coder-data',
      posixUser: { uid: '1000', gid: '1000' },
      createAcl: { ownerUid: '1000', ownerGid: '1000', permissions: '0755' },
    });

    // -----------------------------------------------------------------
    // Fargate Task Definition
    // -----------------------------------------------------------------
    const taskDefinition = new ecs.FargateTaskDefinition(
      this,
      'TaskDefinition',
      {
        family: 'coder-server',
        cpu: 1024,
        memoryLimitMiB: 4096,
        taskRole: props.taskRole,
        executionRole: props.executionRole,
      },
    );

    taskDefinition.addVolume({
      name: 'coder-data',
      efsVolumeConfiguration: {
        fileSystemId: props.fileSystem.fileSystemId,
        transitEncryption: 'ENABLED',
        authorizationConfig: {
          accessPointId: accessPoint.accessPointId,
          iam: 'ENABLED',
        },
      },
    });

    // -----------------------------------------------------------------
    // Container
    // -----------------------------------------------------------------
    const container = taskDefinition.addContainer('coder', {
      image: ecs.ContainerImage.fromRegistry(config.coderImage),
      portMappings: [{ containerPort: 7080, protocol: ecs.Protocol.TCP }],
      environment: {
        CODER_ACCESS_URL: `https://coder.${baseDomain}`,
        CODER_WILDCARD_ACCESS_URL: `*.${baseDomain}`,
        CODER_HTTP_ADDRESS: '0.0.0.0:7080',
        CODER_SECURE_AUTH_COOKIE: 'true',
        CODER_OIDC_ISSUER_URL: config.oidcIssuerUrl,
        CODER_OIDC_ALLOW_SIGNUPS: 'true',
        CODER_OIDC_SCOPES: 'openid,profile,email',
        CODER_TELEMETRY: 'false',
        CODER_CACHE_DIRECTORY: '/home/coder/.cache/coder',
      },
      secrets: {
        CODER_PG_CONNECTION_URL: ecs.Secret.fromSecretsManager(
          props.databaseSecret,
        ),
        CODER_OIDC_CLIENT_ID: ecs.Secret.fromSecretsManager(
          props.secrets['coder/oidc'],
          'client_id',
        ),
        CODER_OIDC_CLIENT_SECRET: ecs.Secret.fromSecretsManager(
          props.secrets['coder/oidc'],
          'client_secret',
        ),
      },
      logging: ecs.LogDrivers.awsLogs({ streamPrefix: 'coder' }),
      healthCheck: {
        command: [
          'CMD-SHELL',
          'curl -f http://localhost:7080/api/v2/buildinfo || exit 1',
        ],
        interval: Duration.seconds(30),
        timeout: Duration.seconds(5),
        retries: 3,
        startPeriod: Duration.seconds(60),
      },
    });

    container.addMountPoints({
      containerPath: '/home/coder/.config/coderv2',
      sourceVolume: 'coder-data',
      readOnly: false,
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
        name: 'coder',
      },
      circuitBreaker: { enable: true, rollback: true },
    });

    // -----------------------------------------------------------------
    // ALB Target Group
    // -----------------------------------------------------------------
    this.targetGroup = new elbv2.ApplicationTargetGroup(this, 'TargetGroup', {
      port: 7080,
      protocol: elbv2.ApplicationProtocol.HTTP,
      vpc: props.vpc,
      targets: [this.service],
      healthCheck: {
        path: '/api/v2/buildinfo',
        interval: Duration.seconds(30),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
      deregistrationDelay: Duration.seconds(30),
    });

    // -----------------------------------------------------------------
    // ALB Listener Rules
    // -----------------------------------------------------------------
    new elbv2.ApplicationListenerRule(this, 'CoderHostRule', {
      listener: props.listener,
      priority: 100,
      conditions: [elbv2.ListenerCondition.hostHeaders([`coder.${baseDomain}`])],
      action: elbv2.ListenerAction.forward([this.targetGroup]),
    });

    new elbv2.ApplicationListenerRule(this, 'WildcardHostRule', {
      listener: props.listener,
      priority: 500,
      conditions: [elbv2.ListenerCondition.hostHeaders([`*.${baseDomain}`])],
      action: elbv2.ListenerAction.forward([this.targetGroup]),
    });
  }
}
