import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as elasticache from 'aws-cdk-lib/aws-elasticache';
import * as efs from 'aws-cdk-lib/aws-efs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { Construct } from 'constructs';
import { EnvironmentConfig } from '../config/environment.js';
import { NetworkStackOutputs } from './network-stack.js';

export interface DataStackProps extends cdk.StackProps {
  config: EnvironmentConfig;
  network: NetworkStackOutputs;
}

export interface DataStackOutputs {
  database: {
    instance: rds.IDatabaseInstance;
    secret: secretsmanager.ISecret;
  };
  redis: {
    endpoint: string;
    port: number;
  };
  fileSystem: efs.IFileSystem;
  buckets: {
    terraformState: s3.IBucket;
    backups: s3.IBucket;
    artifacts: s3.IBucket;
    langfuseEvents: s3.IBucket;
    langfuseMedia: s3.IBucket;
  };
  secrets: Record<string, secretsmanager.ISecret>;
}

export class DataStack extends cdk.Stack {
  public readonly outputs: DataStackOutputs;

  constructor(scope: Construct, id: string, props: DataStackProps) {
    super(scope, id, props);

    const { config, network } = props;

    // Apply tags to all resources in this stack
    for (const [key, value] of Object.entries(config.tags)) {
      cdk.Tags.of(this).add(key, value);
    }

    // ---------------------------------------------------------------
    // RDS PostgreSQL 16
    // ---------------------------------------------------------------
    const parameterGroup = new rds.ParameterGroup(this, 'PostgresParams', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_16,
      }),
      parameters: {
        'rds.force_ssl': '1',
      },
    });

    const dbInstance = new rds.DatabaseInstance(this, 'Database', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_16,
      }),
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.R6G,
        ec2.InstanceSize.LARGE,
      ),
      allocatedStorage: config.rdsAllocatedStorage,
      maxAllocatedStorage: config.rdsMaxAllocatedStorage,
      storageType: rds.StorageType.GP3,
      credentials: rds.Credentials.fromGeneratedSecret('postgres'),
      vpc: network.vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
      securityGroups: [network.securityGroups.rds],
      multiAz: false,
      backupRetention: cdk.Duration.days(30),
      deletionProtection: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      parameterGroup,
      storageEncrypted: true,
      cloudwatchLogsExports: ['postgresql'],
      enablePerformanceInsights: true,
    });

    // ---------------------------------------------------------------
    // ElastiCache Redis 7.x
    // ---------------------------------------------------------------
    const redisSubnetGroup = new elasticache.CfnSubnetGroup(
      this,
      'RedisSubnetGroup',
      {
        description: 'Subnet group for Redis in PrivateData subnets',
        subnetIds: network.vpc.selectSubnets({
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        }).subnetIds,
      },
    );

    const redisReplicationGroup = new elasticache.CfnReplicationGroup(
      this,
      'RedisReplicationGroup',
      {
        replicationGroupDescription: 'Redis cluster for Coder platform',
        engine: 'redis',
        engineVersion: '7.1',
        replicasPerNodeGroup: 1,
        automaticFailoverEnabled: true,
        multiAzEnabled: true,
        cacheNodeType: config.redisNodeType,
        atRestEncryptionEnabled: true,
        transitEncryptionEnabled: true,
        cacheSubnetGroupName: redisSubnetGroup.ref,
        securityGroupIds: [
          network.securityGroups.redis.securityGroupId,
        ],
        snapshotRetentionLimit: 7,
        snapshotWindow: '03:00-04:00',
        preferredMaintenanceWindow: 'sun:04:30-sun:05:30',
      },
    );

    // ---------------------------------------------------------------
    // EFS
    // ---------------------------------------------------------------
    const fileSystem = new efs.FileSystem(this, 'FileSystem', {
      vpc: network.vpc,
      performanceMode: efs.PerformanceMode.GENERAL_PURPOSE,
      throughputMode: efs.ThroughputMode.BURSTING,
      encrypted: true,
      lifecyclePolicy: efs.LifecyclePolicy.AFTER_30_DAYS,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      securityGroup: network.securityGroups.efs,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
    });

    // ---------------------------------------------------------------
    // S3 Buckets
    // ---------------------------------------------------------------
    const sharedBucketProps: Partial<s3.BucketProps> = {
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    };

    const terraformStateBucket = new s3.Bucket(this, 'TerraformStateBucket', {
      ...sharedBucketProps,
      bucketName: `${config.project}-terraform-state`,
    });

    const backupsBucket = new s3.Bucket(this, 'BackupsBucket', {
      ...sharedBucketProps,
      bucketName: `${config.project}-backups`,
      lifecycleRules: [
        {
          noncurrentVersionExpiration: cdk.Duration.days(90),
        },
      ],
    });

    const artifactsBucket = new s3.Bucket(this, 'ArtifactsBucket', {
      ...sharedBucketProps,
      bucketName: `${config.project}-artifacts`,
    });

    const langfuseEventsBucket = new s3.Bucket(
      this,
      'LangfuseEventsBucket',
      {
        ...sharedBucketProps,
        bucketName: `${config.project}-langfuse-events`,
      },
    );

    const langfuseMediaBucket = new s3.Bucket(this, 'LangfuseMediaBucket', {
      ...sharedBucketProps,
      bucketName: `${config.project}-langfuse-media`,
    });

    // ---------------------------------------------------------------
    // DynamoDB (Terraform state lock)
    // ---------------------------------------------------------------
    new dynamodb.Table(this, 'TerraformLockTable', {
      tableName: 'terraform-locks',
      partitionKey: { name: 'LockID', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // ---------------------------------------------------------------
    // Secrets Manager
    // ---------------------------------------------------------------
    const secrets: Record<string, secretsmanager.ISecret> = {};

    secrets['coder/oidc'] = new secretsmanager.Secret(this, 'CoderOidcSecret', {
      secretName: 'prod/coder/oidc',
      secretStringValue: cdk.SecretValue.unsafePlainText(
        JSON.stringify({ client_id: '', client_secret: '' }),
      ),
      description: 'Coder OIDC client credentials (Azure AD)',
    });

    secrets['litellm/master-key'] = new secretsmanager.Secret(
      this,
      'LitellmMasterKeySecret',
      {
        secretName: 'prod/litellm/master-key',
        generateSecretString: {
          secretStringTemplate: JSON.stringify({}),
          generateStringKey: 'key',
          excludePunctuation: true,
          passwordLength: 32,
        },
        description: 'LiteLLM master API key',
      },
    );

    secrets['litellm/anthropic-api-key'] = new secretsmanager.Secret(
      this,
      'LitellmAnthropicKeySecret',
      {
        secretName: 'prod/litellm/anthropic-api-key',
        secretStringValue: cdk.SecretValue.unsafePlainText(''),
        description: 'Anthropic API key for LiteLLM proxy',
      },
    );

    secrets['litellm/database'] = new secretsmanager.Secret(
      this,
      'LitellmDatabaseSecret',
      {
        secretName: 'prod/litellm/database',
        secretStringValue: cdk.SecretValue.unsafePlainText(''),
        description:
          'LiteLLM database connection string (constructed from RDS endpoint)',
      },
    );

    secrets['key-provisioner/secret'] = new secretsmanager.Secret(
      this,
      'KeyProvisionerSecret',
      {
        secretName: 'prod/key-provisioner/secret',
        generateSecretString: {
          excludePunctuation: true,
          passwordLength: 48,
        },
        description: 'Key provisioner authentication secret',
      },
    );

    secrets['langfuse/api-keys'] = new secretsmanager.Secret(
      this,
      'LangfuseApiKeysSecret',
      {
        secretName: 'prod/langfuse/api-keys',
        generateSecretString: {
          secretStringTemplate: JSON.stringify({}),
          generateStringKey: 'secret_key',
          excludePunctuation: true,
          passwordLength: 32,
        },
        description: 'Langfuse API keys',
      },
    );

    secrets['langfuse/auth'] = new secretsmanager.Secret(
      this,
      'LangfuseAuthSecret',
      {
        secretName: 'prod/langfuse/auth',
        generateSecretString: {
          secretStringTemplate: JSON.stringify({}),
          generateStringKey: 'nextauth_secret',
          excludePunctuation: true,
          passwordLength: 32,
        },
        description: 'Langfuse NextAuth secret',
      },
    );

    secrets['langfuse/database'] = new secretsmanager.Secret(
      this,
      'LangfuseDatabaseSecret',
      {
        secretName: 'prod/langfuse/database',
        secretStringValue: cdk.SecretValue.unsafePlainText(''),
        description:
          'Langfuse database connection string (constructed from RDS endpoint)',
      },
    );

    secrets['langfuse/clickhouse'] = new secretsmanager.Secret(
      this,
      'LangfuseClickhouseSecret',
      {
        secretName: 'prod/langfuse/clickhouse',
        generateSecretString: {
          excludePunctuation: true,
          passwordLength: 32,
        },
        description: 'Langfuse ClickHouse credentials',
      },
    );

    secrets['custom-llm/api-key'] = new secretsmanager.Secret(
      this,
      'CustomLlmApiKeySecret',
      {
        secretName: 'prod/custom-llm/api-key',
        secretStringValue: cdk.SecretValue.unsafePlainText(''),
        description: 'Corporate proxy API key for custom LLM endpoint',
      },
    );

    // ---------------------------------------------------------------
    // Stack outputs
    // ---------------------------------------------------------------
    this.outputs = {
      database: {
        instance: dbInstance,
        secret: dbInstance.secret!,
      },
      redis: {
        endpoint: redisReplicationGroup.attrPrimaryEndPointAddress,
        port: 6379,
      },
      fileSystem,
      buckets: {
        terraformState: terraformStateBucket,
        backups: backupsBucket,
        artifacts: artifactsBucket,
        langfuseEvents: langfuseEventsBucket,
        langfuseMedia: langfuseMediaBucket,
      },
      secrets,
    };
  }
}
