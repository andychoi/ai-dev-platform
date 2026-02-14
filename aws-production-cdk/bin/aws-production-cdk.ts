#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { NetworkStack } from '../lib/stacks/network-stack';
import { DataStack } from '../lib/stacks/data-stack';
import { PlatformStack } from '../lib/stacks/platform-stack';
import { ObservabilityStack } from '../lib/stacks/observability-stack';
import { productionConfig } from '../lib/config/environment';

const app = new cdk.App();

const env = {
  account: productionConfig.account || process.env.CDK_DEFAULT_ACCOUNT,
  region: productionConfig.region,
};

const network = new NetworkStack(app, 'NetworkStack', {
  env,
  config: productionConfig,
});

const data = new DataStack(app, 'DataStack', {
  env,
  config: productionConfig,
  network: network.outputs,
});

const platform = new PlatformStack(app, 'PlatformStack', {
  env,
  config: productionConfig,
  network: network.outputs,
  data: data.outputs,
});

const observability = new ObservabilityStack(app, 'ObservabilityStack', {
  env,
  config: productionConfig,
  network: network.outputs,
  data: data.outputs,
  platform: platform.outputs,
});

// Explicit dependencies (CDK infers from cross-stack refs, but be explicit)
data.addDependency(network);
platform.addDependency(data);
observability.addDependency(platform);

app.synth();
