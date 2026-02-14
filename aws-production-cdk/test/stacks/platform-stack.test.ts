import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { NetworkStack } from '../../lib/stacks/network-stack.js';
import { DataStack } from '../../lib/stacks/data-stack.js';
import { PlatformStack } from '../../lib/stacks/platform-stack.js';
import { productionConfig } from '../../lib/config/environment.js';

describe('PlatformStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-west-2' };
    const network = new NetworkStack(app, 'Net', { env, config: productionConfig });
    const data = new DataStack(app, 'Data', { env, config: productionConfig, network: network.outputs });
    const platform = new PlatformStack(app, 'Platform', { env, config: productionConfig, network: network.outputs, data: data.outputs });
    template = Template.fromStack(platform);
  });

  test('creates ECS cluster with container insights', () => {
    template.hasResourceProperties('AWS::ECS::Cluster', {
      ClusterSettings: [{ Name: 'containerInsights', Value: 'enabled' }],
    });
  });

  test('creates internal ALB', () => {
    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::LoadBalancer', {
      Scheme: 'internal',
      Type: 'application',
    });
  });

  test('creates HTTPS listener on port 443', () => {
    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::Listener', {
      Port: 443,
      Protocol: 'HTTPS',
    });
  });

  test('creates ACM certificate', () => {
    template.resourceCountIs('AWS::CertificateManager::Certificate', 1);
  });

  test('creates SSM parameters for workspace bridge', () => {
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/coder-production/cluster-arn',
    });
  });

  test('creates IAM roles for ECS tasks', () => {
    const roles = template.findResources('AWS::IAM::Role');
    expect(Object.keys(roles).length).toBeGreaterThanOrEqual(3);
  });
});
