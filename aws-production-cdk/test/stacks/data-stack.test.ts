import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { NetworkStack } from '../../lib/stacks/network-stack.js';
import { DataStack } from '../../lib/stacks/data-stack.js';
import { productionConfig } from '../../lib/config/environment.js';

describe('DataStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const network = new NetworkStack(app, 'TestNetwork', {
      env: { account: '123456789012', region: 'us-west-2' },
      config: productionConfig,
    });
    const data = new DataStack(app, 'TestData', {
      env: { account: '123456789012', region: 'us-west-2' },
      config: productionConfig,
      network: network.outputs,
    });
    template = Template.fromStack(data);
  });

  test('creates RDS PostgreSQL 16 instance', () => {
    template.hasResourceProperties('AWS::RDS::DBInstance', {
      Engine: 'postgres',
      DBInstanceClass: 'db.r6g.large',
      StorageEncrypted: true,
      DeletionProtection: true,
    });
  });

  test('creates ElastiCache Redis replication group', () => {
    template.hasResourceProperties('AWS::ElastiCache::ReplicationGroup', {
      Engine: 'redis',
      AtRestEncryptionEnabled: true,
      TransitEncryptionEnabled: true,
      AutomaticFailoverEnabled: true,
    });
  });

  test('creates EFS file system with encryption', () => {
    template.hasResourceProperties('AWS::EFS::FileSystem', {
      Encrypted: true,
      PerformanceMode: 'generalPurpose',
      ThroughputMode: 'bursting',
    });
  });

  test('creates EFS mount targets in app subnets', () => {
    template.resourceCountIs('AWS::EFS::MountTarget', 2);
  });

  test('creates 5 S3 buckets', () => {
    template.resourceCountIs('AWS::S3::Bucket', 5);
  });

  test('creates DynamoDB lock table', () => {
    template.hasResourceProperties('AWS::DynamoDB::Table', {
      TableName: 'terraform-locks',
      KeySchema: [{ AttributeName: 'LockID', KeyType: 'HASH' }],
    });
  });

  test('creates Secrets Manager secrets', () => {
    const secrets = template.findResources('AWS::SecretsManager::Secret');
    expect(Object.keys(secrets).length).toBeGreaterThanOrEqual(8);
  });
});
