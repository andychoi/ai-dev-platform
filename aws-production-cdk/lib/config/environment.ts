// aws-production-cdk/lib/config/environment.ts

export interface EnvironmentConfig {
  // AWS account & region
  account: string;
  region: string;

  // Naming
  project: string;
  environment: string;

  // Networking
  vpcCidr: string;
  availabilityZones: string[];

  // Domain
  domain: string;
  hostedZoneId: string; // Route53 hosted zone (empty = skip DNS validation)

  // RDS
  rdsInstanceClass: string;
  rdsAllocatedStorage: number;
  rdsMaxAllocatedStorage: number;

  // ElastiCache
  redisNodeType: string;

  // Container images
  coderImage: string;
  litellmImage: string;
  keyProvisionerImage: string;
  langfuseImage: string;
  clickhouseImage: string;

  // OIDC (Azure AD)
  oidcIssuerUrl: string;
  oidcAuthorizationEndpoint: string;
  oidcTokenEndpoint: string;
  oidcUserInfoEndpoint: string;

  // Feature flags
  enableDockerWorkspaces: boolean;
  enableWorkspaceDirectAccess: boolean;

  // Custom LLM
  customLlmApiBase: string;

  // Tags
  tags: Record<string, string>;
}

export const productionConfig: EnvironmentConfig = {
  account: process.env.CDK_DEFAULT_ACCOUNT || '',
  region: 'us-west-2',

  project: 'coder',
  environment: 'production',

  vpcCidr: '10.0.0.0/16',
  availabilityZones: ['us-west-2a', 'us-west-2b'],

  domain: 'coder.company.com',
  hostedZoneId: '',

  rdsInstanceClass: 'r6g.large',
  rdsAllocatedStorage: 100,
  rdsMaxAllocatedStorage: 500,

  redisNodeType: 'cache.r6g.large',

  coderImage: 'ghcr.io/coder/coder:latest',
  litellmImage: 'ghcr.io/berriai/litellm:main-latest',
  keyProvisionerImage: '', // Built from shared/key-provisioner
  langfuseImage: 'langfuse/langfuse:latest',
  clickhouseImage: 'clickhouse/clickhouse-server:24-alpine',

  oidcIssuerUrl: 'https://login.microsoftonline.com/{tenant-id}/v2.0',
  oidcAuthorizationEndpoint: 'https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/authorize',
  oidcTokenEndpoint: 'https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/token',
  oidcUserInfoEndpoint: 'https://graph.microsoft.com/oidc/userinfo',

  enableDockerWorkspaces: false,
  enableWorkspaceDirectAccess: true,

  customLlmApiBase: 'https://h-chat-api.autoever.com/v2/api',

  tags: {
    Project: 'coder-webide',
    Environment: 'production',
    ManagedBy: 'cdk',
  },
};
