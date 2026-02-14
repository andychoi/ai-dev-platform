import { Duration, RemovalPolicy } from 'aws-cdk-lib';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as efs from 'aws-cdk-lib/aws-efs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as servicediscovery from 'aws-cdk-lib/aws-servicediscovery';
import { Construct } from 'constructs';
import { EnvironmentConfig } from '../config/environment.js';

export interface LangfuseServiceProps {
  config: EnvironmentConfig;
  cluster: ecs.ICluster;
  vpc: ec2.IVpc;
  listener: elbv2.IApplicationListener;
  executionRole: iam.IRole;
  taskRole: iam.IRole;
  securityGroup: ec2.ISecurityGroup;
  namespace: servicediscovery.IPrivateDnsNamespace;
  secrets: Record<string, secretsmanager.ISecret>;
  fileSystem: efs.IFileSystem;
  redis: { endpoint: string; port: number };
  buckets: { langfuseEvents: s3.IBucket; langfuseMedia: s3.IBucket };
}

/**
 * LangfuseService encapsulates the full Langfuse observability stack:
 * ClickHouse (analytics DB), Langfuse Web (UI/API), and Langfuse Worker
 * (background processing). All three run as separate ECS Fargate services.
 *
 * The execution role and task role are imported as immutable references to
 * avoid cross-stack cyclic dependencies. The PlatformStack already grants
 * broad permissions on logs and secrets, so no additional grants are needed.
 */
export class LangfuseService extends Construct {
  public readonly service: ecs.FargateService;
  public readonly targetGroup: elbv2.ApplicationTargetGroup;

  constructor(scope: Construct, id: string, props: LangfuseServiceProps) {
    super(scope, id);

    const { config } = props;

    // Derive baseDomain: 'coder.company.com' -> 'company.com'
    const domainParts = config.domain.split('.');
    const baseDomain =
      domainParts.length > 2
        ? domainParts.slice(1).join('.')
        : config.domain;

    // Import roles as immutable to prevent CDK from adding grants that
    // would create cyclic cross-stack references. The PlatformStack
    // already provides broad permissions (logs:*, secretsmanager:GetSecretValue
    // on prod/*) on these roles.
    const executionRole = iam.Role.fromRoleArn(
      this,
      'ImportedExecutionRole',
      props.executionRole.roleArn,
      { mutable: false },
    );
    const taskRole = iam.Role.fromRoleArn(
      this,
      'ImportedTaskRole',
      props.taskRole.roleArn,
      { mutable: false },
    );

    // -----------------------------------------------------------------
    // Log Groups (explicit to keep all resources in this stack)
    // -----------------------------------------------------------------
    const clickhouseLogGroup = new logs.LogGroup(this, 'ClickHouseLogGroup', {
      logGroupName: '/ecs/clickhouse',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    const langfuseWebLogGroup = new logs.LogGroup(this, 'LangfuseWebLogGroup', {
      logGroupName: '/ecs/langfuse-web',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    const langfuseWorkerLogGroup = new logs.LogGroup(
      this,
      'LangfuseWorkerLogGroup',
      {
        logGroupName: '/ecs/langfuse-worker',
        retention: logs.RetentionDays.ONE_MONTH,
        removalPolicy: RemovalPolicy.DESTROY,
      },
    );

    // =================================================================
    // ClickHouse Service
    // =================================================================

    // -----------------------------------------------------------------
    // EFS Access Point
    // -----------------------------------------------------------------
    const clickhouseAccessPoint = new efs.AccessPoint(
      this,
      'ClickHouseDataAccessPoint',
      {
        fileSystem: props.fileSystem,
        path: '/clickhouse-data',
        posixUser: { uid: '101', gid: '101' },
        createAcl: { ownerUid: '101', ownerGid: '101', permissions: '0750' },
      },
    );

    // -----------------------------------------------------------------
    // ClickHouse Task Definition
    // -----------------------------------------------------------------
    const clickhouseTaskDef = new ecs.FargateTaskDefinition(
      this,
      'ClickHouseTaskDefinition',
      {
        family: 'clickhouse',
        cpu: 1024,
        memoryLimitMiB: 4096,
        taskRole,
        executionRole,
      },
    );

    clickhouseTaskDef.addVolume({
      name: 'clickhouse-data',
      efsVolumeConfiguration: {
        fileSystemId: props.fileSystem.fileSystemId,
        transitEncryption: 'ENABLED',
        authorizationConfig: {
          accessPointId: clickhouseAccessPoint.accessPointId,
          iam: 'ENABLED',
        },
      },
    });

    const clickhouseContainer = clickhouseTaskDef.addContainer('clickhouse', {
      image: ecs.ContainerImage.fromRegistry(config.clickhouseImage),
      portMappings: [
        { containerPort: 8123, protocol: ecs.Protocol.TCP },
        { containerPort: 9000, protocol: ecs.Protocol.TCP },
      ],
      environment: {
        CLICKHOUSE_DB: 'langfuse',
        CLICKHOUSE_USER: 'langfuse',
      },
      secrets: {
        CLICKHOUSE_PASSWORD: ecs.Secret.fromSecretsManager(
          props.secrets['langfuse/clickhouse'],
        ),
      },
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'clickhouse',
        logGroup: clickhouseLogGroup,
      }),
      healthCheck: {
        command: [
          'CMD-SHELL',
          'wget -qO- http://localhost:8123/ping || exit 1',
        ],
        interval: Duration.seconds(30),
        timeout: Duration.seconds(5),
        retries: 3,
        startPeriod: Duration.seconds(60),
      },
    });

    clickhouseContainer.addMountPoints({
      containerPath: '/var/lib/clickhouse',
      sourceVolume: 'clickhouse-data',
      readOnly: false,
    });

    // -----------------------------------------------------------------
    // ClickHouse Fargate Service
    // -----------------------------------------------------------------
    new ecs.FargateService(this, 'ClickHouseService', {
      cluster: props.cluster,
      taskDefinition: clickhouseTaskDef,
      desiredCount: 1,
      securityGroups: [props.securityGroup],
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      capacityProviderStrategies: [
        { capacityProvider: 'FARGATE', weight: 1 },
      ],
      cloudMapOptions: {
        cloudMapNamespace: props.namespace,
        name: 'clickhouse',
      },
      circuitBreaker: { enable: true, rollback: true },
    });

    // =================================================================
    // Shared Langfuse environment & secrets (Web + Worker)
    // =================================================================
    const langfuseEnvironment: Record<string, string> = {
      NEXTAUTH_URL: `https://langfuse.${baseDomain}`,
      NODE_ENV: 'production',
      CLICKHOUSE_URL: 'http://clickhouse.coder-production.local:8123',
      CLICKHOUSE_MIGRATION_URL:
        'clickhouse://clickhouse.coder-production.local:9000',
      REDIS_CONNECTION_STRING: `rediss://${props.redis.endpoint}:${props.redis.port}`,
      LANGFUSE_S3_EVENT_UPLOAD_BUCKET:
        props.buckets.langfuseEvents.bucketName,
      LANGFUSE_S3_MEDIA_UPLOAD_BUCKET:
        props.buckets.langfuseMedia.bucketName,
      LANGFUSE_S3_EVENT_UPLOAD_ENABLED: 'true',
      LANGFUSE_S3_MEDIA_UPLOAD_ENABLED: 'true',
    };

    const langfuseSecrets: Record<string, ecs.Secret> = {
      NEXTAUTH_SECRET: ecs.Secret.fromSecretsManager(
        props.secrets['langfuse/auth'],
        'nextauth_secret',
      ),
      DATABASE_URL: ecs.Secret.fromSecretsManager(
        props.secrets['langfuse/database'],
      ),
      CLICKHOUSE_PASSWORD: ecs.Secret.fromSecretsManager(
        props.secrets['langfuse/clickhouse'],
      ),
      SALT: ecs.Secret.fromSecretsManager(
        props.secrets['langfuse/auth'],
        'nextauth_secret',
      ),
    };

    // =================================================================
    // Langfuse Web Service
    // =================================================================

    // -----------------------------------------------------------------
    // Langfuse Web Task Definition
    // -----------------------------------------------------------------
    const webTaskDef = new ecs.FargateTaskDefinition(
      this,
      'LangfuseWebTaskDefinition',
      {
        family: 'langfuse-web',
        cpu: 1024,
        memoryLimitMiB: 2048,
        taskRole,
        executionRole,
      },
    );

    webTaskDef.addContainer('langfuse-web', {
      image: ecs.ContainerImage.fromRegistry(config.langfuseImage),
      portMappings: [{ containerPort: 3000, protocol: ecs.Protocol.TCP }],
      environment: langfuseEnvironment,
      secrets: langfuseSecrets,
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'langfuse-web',
        logGroup: langfuseWebLogGroup,
      }),
      healthCheck: {
        command: [
          'CMD-SHELL',
          'wget -qO- http://localhost:3000/api/public/health || exit 1',
        ],
        interval: Duration.seconds(30),
        timeout: Duration.seconds(5),
        retries: 3,
        startPeriod: Duration.seconds(60),
      },
    });

    // -----------------------------------------------------------------
    // Langfuse Web Fargate Service
    // -----------------------------------------------------------------
    this.service = new ecs.FargateService(this, 'LangfuseWebService', {
      cluster: props.cluster,
      taskDefinition: webTaskDef,
      desiredCount: 1,
      securityGroups: [props.securityGroup],
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      capacityProviderStrategies: [
        { capacityProvider: 'FARGATE', weight: 1 },
      ],
      cloudMapOptions: {
        cloudMapNamespace: props.namespace,
        name: 'langfuse-web',
      },
      circuitBreaker: { enable: true, rollback: true },
    });

    // -----------------------------------------------------------------
    // ALB Target Group
    // -----------------------------------------------------------------
    this.targetGroup = new elbv2.ApplicationTargetGroup(
      this,
      'LangfuseWebTargetGroup',
      {
        port: 3000,
        protocol: elbv2.ApplicationProtocol.HTTP,
        vpc: props.vpc,
        targets: [this.service],
        healthCheck: {
          path: '/api/public/health',
          interval: Duration.seconds(30),
          healthyThresholdCount: 2,
          unhealthyThresholdCount: 3,
        },
        deregistrationDelay: Duration.seconds(30),
      },
    );

    // -----------------------------------------------------------------
    // ALB Listener Rule
    // -----------------------------------------------------------------
    new elbv2.ApplicationListenerRule(this, 'LangfuseHostRule', {
      listener: props.listener,
      priority: 300,
      conditions: [
        elbv2.ListenerCondition.hostHeaders([`langfuse.${baseDomain}`]),
      ],
      action: elbv2.ListenerAction.forward([this.targetGroup]),
    });

    // =================================================================
    // Langfuse Worker Service
    // =================================================================

    // -----------------------------------------------------------------
    // Langfuse Worker Task Definition
    // -----------------------------------------------------------------
    const workerTaskDef = new ecs.FargateTaskDefinition(
      this,
      'LangfuseWorkerTaskDefinition',
      {
        family: 'langfuse-worker',
        cpu: 512,
        memoryLimitMiB: 1024,
        taskRole,
        executionRole,
      },
    );

    workerTaskDef.addContainer('langfuse-worker', {
      image: ecs.ContainerImage.fromRegistry(config.langfuseImage),
      portMappings: [{ containerPort: 3030, protocol: ecs.Protocol.TCP }],
      environment: {
        ...langfuseEnvironment,
        LANGFUSE_WORKER_PORT: '3030',
      },
      secrets: langfuseSecrets,
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'langfuse-worker',
        logGroup: langfuseWorkerLogGroup,
      }),
      healthCheck: {
        command: [
          'CMD-SHELL',
          'wget -qO- http://localhost:3030/api/public/health || exit 1',
        ],
        interval: Duration.seconds(30),
        timeout: Duration.seconds(5),
        retries: 3,
        startPeriod: Duration.seconds(60),
      },
    });

    // -----------------------------------------------------------------
    // Langfuse Worker Fargate Service
    // -----------------------------------------------------------------
    new ecs.FargateService(this, 'LangfuseWorkerService', {
      cluster: props.cluster,
      taskDefinition: workerTaskDef,
      desiredCount: 1,
      securityGroups: [props.securityGroup],
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      capacityProviderStrategies: [
        { capacityProvider: 'FARGATE', weight: 1 },
      ],
      cloudMapOptions: {
        cloudMapNamespace: props.namespace,
        name: 'langfuse-worker',
      },
      circuitBreaker: { enable: true, rollback: true },
    });
  }
}
