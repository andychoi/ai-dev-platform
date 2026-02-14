import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { EnvironmentConfig } from '../config/environment.js';
import { NetworkStackOutputs } from './network-stack.js';
import { DataStackOutputs } from './data-stack.js';
import { PlatformStackOutputs } from './platform-stack.js';
import { LangfuseService } from '../constructs/langfuse-service.js';

export interface ObservabilityStackProps extends cdk.StackProps {
  config: EnvironmentConfig;
  network: NetworkStackOutputs;
  data: DataStackOutputs;
  platform: PlatformStackOutputs;
}

export class ObservabilityStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: ObservabilityStackProps) {
    super(scope, id, props);

    const { config, network, data, platform } = props;

    // Apply tags to all resources in this stack
    for (const [key, value] of Object.entries(config.tags)) {
      cdk.Tags.of(this).add(key, value);
    }

    // ---------------------------------------------------------------
    // Langfuse + ClickHouse
    // ---------------------------------------------------------------
    new LangfuseService(this, 'LangfuseService', {
      config,
      cluster: platform.cluster,
      vpc: network.vpc,
      listener: platform.listener,
      executionRole: platform.executionRole,
      taskRole: platform.taskRoles.langfuse,
      securityGroup: network.securityGroups.ecsServices,
      namespace: network.namespace,
      secrets: data.secrets,
      fileSystem: data.fileSystem,
      redis: data.redis,
      buckets: {
        langfuseEvents: data.buckets.langfuseEvents,
        langfuseMedia: data.buckets.langfuseMedia,
      },
    });
  }
}
