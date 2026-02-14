import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as efs from 'aws-cdk-lib/aws-efs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as servicediscovery from 'aws-cdk-lib/aws-servicediscovery';
import { ObservabilityStack } from '../../lib/stacks/observability-stack.js';
import { productionConfig } from '../../lib/config/environment.js';

describe('ObservabilityStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-west-2' };

    // Create a helper stack to hold upstream resources, avoiding
    // cross-stack cyclic dependency issues during synthesis.
    const deps = new cdk.Stack(app, 'Deps', { env });

    const vpc = new ec2.Vpc(deps, 'Vpc');
    const sgEcsServices = new ec2.SecurityGroup(deps, 'SgEcs', { vpc });
    const namespace = new servicediscovery.PrivateDnsNamespace(deps, 'Ns', {
      name: 'coder-production.local',
      vpc,
    });
    const fileSystem = new efs.FileSystem(deps, 'Efs', { vpc });
    const cluster = new ecs.Cluster(deps, 'Cluster', {
      vpc,
      enableFargateCapacityProviders: true,
    });
    const certificate = new acm.Certificate(deps, 'Cert', {
      domainName: 'coder.company.com',
    });
    const alb = new elbv2.ApplicationLoadBalancer(deps, 'Alb', {
      vpc,
      internetFacing: false,
    });
    const listener = alb.addListener('Listener', {
      port: 443,
      protocol: elbv2.ApplicationProtocol.HTTPS,
      certificates: [certificate],
      defaultAction: elbv2.ListenerAction.fixedResponse(404),
    });
    const executionRole = new iam.Role(deps, 'ExecRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
    });
    const langfuseTaskRole = new iam.Role(deps, 'LangfuseRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
    });
    const langfuseEvtBucket = new s3.Bucket(deps, 'EvtBucket');
    const langfuseMediaBucket = new s3.Bucket(deps, 'MediaBucket');

    const secrets: Record<string, secretsmanager.ISecret> = {};
    secrets['langfuse/clickhouse'] = new secretsmanager.Secret(deps, 'ChSec', {
      secretName: 'prod/langfuse/clickhouse',
    });
    secrets['langfuse/auth'] = new secretsmanager.Secret(deps, 'AuthSec', {
      secretName: 'prod/langfuse/auth',
    });
    secrets['langfuse/database'] = new secretsmanager.Secret(deps, 'DbSec', {
      secretName: 'prod/langfuse/database',
    });

    const obs = new ObservabilityStack(app, 'Obs', {
      env,
      config: productionConfig,
      network: {
        vpc,
        securityGroups: {
          alb: sgEcsServices,
          ecsServices: sgEcsServices,
          ecsWorkspaces: sgEcsServices,
          rds: sgEcsServices,
          redis: sgEcsServices,
          efs: sgEcsServices,
        },
        namespace,
      },
      data: {
        database: {
          instance: {} as any,
          secret: {} as any,
        },
        redis: { endpoint: 'redis.example.com', port: 6379 },
        fileSystem,
        buckets: {
          terraformState: {} as any,
          backups: {} as any,
          artifacts: {} as any,
          langfuseEvents: langfuseEvtBucket,
          langfuseMedia: langfuseMediaBucket,
        },
        secrets,
      },
      platform: {
        cluster,
        alb,
        listener,
        executionRole,
        taskRoles: {
          coder: {} as any,
          litellm: {} as any,
          keyProvisioner: {} as any,
          langfuse: langfuseTaskRole,
          workspace: {} as any,
        },
      },
    });

    template = Template.fromStack(obs);
  });

  test('creates 3 ECS task definitions (ClickHouse, Langfuse Web, Langfuse Worker)', () => {
    template.resourceCountIs('AWS::ECS::TaskDefinition', 3);
  });

  test('creates 3 ECS services', () => {
    template.resourceCountIs('AWS::ECS::Service', 3);
  });

  test('creates Langfuse ALB target group', () => {
    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::TargetGroup', {
      Port: 3000,
      Protocol: 'HTTP',
    });
  });

  test('creates ClickHouse EFS access point', () => {
    template.hasResourceProperties('AWS::EFS::AccessPoint', {
      RootDirectory: {
        Path: '/clickhouse-data',
      },
    });
  });

  test('creates ALB listener rule for langfuse host', () => {
    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::ListenerRule', {
      Priority: 300,
    });
  });

  test('only 1 ALB listener rule (Langfuse Web only, not ClickHouse or Worker)', () => {
    template.resourceCountIs('AWS::ElasticLoadBalancingV2::ListenerRule', 1);
  });
});
