import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { NetworkStack } from '../../lib/stacks/network-stack.js';
import { productionConfig } from '../../lib/config/environment.js';

describe('NetworkStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const stack = new NetworkStack(app, 'TestNetworkStack', {
      env: { account: '123456789012', region: 'us-west-2' },
      config: productionConfig,
    });
    template = Template.fromStack(stack);
  });

  test('creates VPC with correct CIDR', () => {
    template.hasResourceProperties('AWS::EC2::VPC', {
      CidrBlock: '10.0.0.0/16',
      EnableDnsSupport: true,
      EnableDnsHostnames: true,
    });
  });

  test('creates 6 subnets (2 public + 2 private app + 2 private data)', () => {
    template.resourceCountIs('AWS::EC2::Subnet', 6);
  });

  test('creates NAT Gateway', () => {
    template.resourceCountIs('AWS::EC2::NatGateway', 1);
  });

  test('creates Internet Gateway', () => {
    template.resourceCountIs('AWS::EC2::InternetGateway', 1);
  });

  test('creates Cloud Map namespace', () => {
    template.hasResourceProperties('AWS::ServiceDiscovery::PrivateDnsNamespace', {
      Name: 'coder-production.local',
    });
  });

  test('creates security groups', () => {
    const sgs = template.findResources('AWS::EC2::SecurityGroup');
    expect(Object.keys(sgs).length).toBeGreaterThanOrEqual(6);
  });

  test('creates S3 gateway endpoint', () => {
    template.hasResourceProperties('AWS::EC2::VPCEndpoint', {
      VpcEndpointType: 'Gateway',
    });
  });
});
