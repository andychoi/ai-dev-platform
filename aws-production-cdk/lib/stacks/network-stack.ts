import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as servicediscovery from 'aws-cdk-lib/aws-servicediscovery';
import { Construct } from 'constructs';
import { EnvironmentConfig } from '../config/environment.js';

export interface NetworkStackProps extends cdk.StackProps {
  config: EnvironmentConfig;
}

export interface NetworkStackOutputs {
  vpc: ec2.IVpc;
  securityGroups: {
    alb: ec2.ISecurityGroup;
    ecsServices: ec2.ISecurityGroup;
    ecsWorkspaces: ec2.ISecurityGroup;
    rds: ec2.ISecurityGroup;
    redis: ec2.ISecurityGroup;
    efs: ec2.ISecurityGroup;
  };
  namespace: servicediscovery.IPrivateDnsNamespace;
}

export class NetworkStack extends cdk.Stack {
  public readonly outputs: NetworkStackOutputs;

  constructor(scope: Construct, id: string, props: NetworkStackProps) {
    super(scope, id, props);

    const { config } = props;

    // Apply tags to all resources in this stack
    for (const [key, value] of Object.entries(config.tags)) {
      cdk.Tags.of(this).add(key, value);
    }

    // ---------------------------------------------------------------
    // VPC
    // ---------------------------------------------------------------
    const vpc = new ec2.Vpc(this, 'Vpc', {
      ipAddresses: ec2.IpAddresses.cidr(config.vpcCidr),
      availabilityZones: config.availabilityZones,
      enableDnsSupport: true,
      enableDnsHostnames: true,
      natGateways: 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'PrivateApp',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 24,
          name: 'PrivateData',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // ---------------------------------------------------------------
    // Security Groups
    // ---------------------------------------------------------------

    // 1. ALB Security Group
    const sgAlb = new ec2.SecurityGroup(this, 'SgAlb', {
      vpc,
      description: 'Security group for Application Load Balancer',
      allowAllOutbound: false,
    });
    sgAlb.addIngressRule(
      ec2.Peer.ipv4(config.vpcCidr),
      ec2.Port.tcp(443),
      'HTTPS from VPC',
    );
    sgAlb.addEgressRule(
      ec2.Peer.ipv4(config.vpcCidr),
      ec2.Port.allTraffic(),
      'All traffic to VPC',
    );

    // 2. ECS Services Security Group
    const sgEcsServices = new ec2.SecurityGroup(this, 'SgEcsServices', {
      vpc,
      description: 'Security group for ECS service tasks (Coder, LiteLLM, etc.)',
      allowAllOutbound: true,
    });
    // Ingress from ALB on service ports
    const servicePorts = [7080, 4000, 3000, 8100, 8123, 9000, 3030];
    for (const port of servicePorts) {
      sgEcsServices.addIngressRule(
        sgAlb,
        ec2.Port.tcp(port),
        `ALB to service port ${port}`,
      );
    }
    // Inter-service communication (self-referencing)
    sgEcsServices.addIngressRule(
      sgEcsServices,
      ec2.Port.allTraffic(),
      'Inter-service communication',
    );

    // 3. ECS Workspaces Security Group
    const sgEcsWorkspaces = new ec2.SecurityGroup(this, 'SgEcsWorkspaces', {
      vpc,
      description: 'Security group for ECS workspace tasks',
      allowAllOutbound: false,
    });
    sgEcsWorkspaces.addIngressRule(
      sgAlb,
      ec2.Port.tcp(13337),
      'ALB to workspace agent port',
    );
    sgEcsWorkspaces.addEgressRule(
      sgEcsServices,
      ec2.Port.tcp(4000),
      'Workspace to LiteLLM',
    );
    sgEcsWorkspaces.addEgressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'HTTPS outbound',
    );
    sgEcsWorkspaces.addEgressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(53),
      'DNS TCP outbound',
    );
    sgEcsWorkspaces.addEgressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.udp(53),
      'DNS UDP outbound',
    );

    // 4. RDS Security Group
    const sgRds = new ec2.SecurityGroup(this, 'SgRds', {
      vpc,
      description: 'Security group for RDS PostgreSQL',
      allowAllOutbound: false,
    });
    sgRds.addIngressRule(
      sgEcsServices,
      ec2.Port.tcp(5432),
      'ECS services to PostgreSQL',
    );

    // 5. Redis Security Group
    const sgRedis = new ec2.SecurityGroup(this, 'SgRedis', {
      vpc,
      description: 'Security group for ElastiCache Redis',
      allowAllOutbound: false,
    });
    sgRedis.addIngressRule(
      sgEcsServices,
      ec2.Port.tcp(6379),
      'ECS services to Redis',
    );

    // 6. EFS Security Group
    const sgEfs = new ec2.SecurityGroup(this, 'SgEfs', {
      vpc,
      description: 'Security group for EFS',
      allowAllOutbound: false,
    });
    sgEfs.addIngressRule(
      sgEcsServices,
      ec2.Port.tcp(2049),
      'ECS services to EFS',
    );
    sgEfs.addIngressRule(
      sgEcsWorkspaces,
      ec2.Port.tcp(2049),
      'ECS workspaces to EFS',
    );

    // ---------------------------------------------------------------
    // VPC Endpoints
    // ---------------------------------------------------------------
    const privateAppSubnets: ec2.SubnetSelection = {
      subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
    };

    // Gateway endpoint: S3
    vpc.addGatewayEndpoint('S3Endpoint', {
      service: ec2.GatewayVpcEndpointAwsService.S3,
    });

    // Interface endpoints
    const interfaceEndpoints: Array<{
      id: string;
      service: ec2.InterfaceVpcEndpointAwsService;
    }> = [
      { id: 'EcrApiEndpoint', service: ec2.InterfaceVpcEndpointAwsService.ECR },
      { id: 'EcrDockerEndpoint', service: ec2.InterfaceVpcEndpointAwsService.ECR_DOCKER },
      { id: 'SecretsManagerEndpoint', service: ec2.InterfaceVpcEndpointAwsService.SECRETS_MANAGER },
      { id: 'CloudWatchLogsEndpoint', service: ec2.InterfaceVpcEndpointAwsService.CLOUDWATCH_LOGS },
      { id: 'StsEndpoint', service: ec2.InterfaceVpcEndpointAwsService.STS },
      { id: 'EcsEndpoint', service: ec2.InterfaceVpcEndpointAwsService.ECS },
      { id: 'SsmEndpoint', service: ec2.InterfaceVpcEndpointAwsService.SSM },
      { id: 'EfsEndpoint', service: ec2.InterfaceVpcEndpointAwsService.ELASTIC_FILESYSTEM },
    ];

    for (const endpoint of interfaceEndpoints) {
      vpc.addInterfaceEndpoint(endpoint.id, {
        service: endpoint.service,
        subnets: privateAppSubnets,
        securityGroups: [sgEcsServices],
      });
    }

    // Bedrock Runtime endpoint (not available as a built-in constant)
    new ec2.InterfaceVpcEndpoint(this, 'BedrockEndpoint', {
      vpc,
      service: new ec2.InterfaceVpcEndpointService(
        `com.amazonaws.${config.region}.bedrock-runtime`,
      ),
      subnets: privateAppSubnets,
      securityGroups: [sgEcsServices],
    });

    // ---------------------------------------------------------------
    // Cloud Map (Service Discovery)
    // ---------------------------------------------------------------
    const namespace = new servicediscovery.PrivateDnsNamespace(
      this,
      'Namespace',
      {
        name: `${config.project}-${config.environment}.local`,
        vpc,
      },
    );

    // ---------------------------------------------------------------
    // Stack outputs
    // ---------------------------------------------------------------
    this.outputs = {
      vpc,
      securityGroups: {
        alb: sgAlb,
        ecsServices: sgEcsServices,
        ecsWorkspaces: sgEcsWorkspaces,
        rds: sgRds,
        redis: sgRedis,
        efs: sgEfs,
      },
      namespace,
    };
  }
}
