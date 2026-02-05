---
name: minio
description: MinIO S3-compatible storage - bucket management, OIDC authentication, workspace integration
---

# MinIO S3 Storage Skill

## Overview

MinIO provides S3-compatible object storage for the POC, with OIDC authentication via Authentik.

## Access

| Endpoint | URL | Purpose |
|----------|-----|---------|
| Console | http://localhost:9001 | Web UI |
| S3 API | http://localhost:9002 | S3-compatible API |
| Health | http://localhost:9002/minio/health/live | Health check |

## Credentials

### Admin Account

| Field | Value |
|-------|-------|
| Username | `minioadmin` |
| Password | `minioadmin` |

### OIDC Login

Users can also login via "Login with SSO" using Authentik credentials.

## OIDC Configuration

```yaml
MINIO_IDENTITY_OPENID_CONFIG_URL: http://authentik-server:9000/application/o/minio/.well-known/openid-configuration
MINIO_IDENTITY_OPENID_CLIENT_ID: minio
MINIO_IDENTITY_OPENID_CLIENT_SECRET: <secret>
MINIO_IDENTITY_OPENID_CLAIM_NAME: policy
MINIO_IDENTITY_OPENID_REDIRECT_URI: http://localhost:9001/oauth_callback
```

## Usage in Workspaces

### Environment Variables

```bash
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export AWS_ENDPOINT_URL=http://minio:9002
```

### AWS CLI

```bash
aws --endpoint-url http://minio:9002 s3 ls
aws --endpoint-url http://minio:9002 s3 mb s3://my-bucket
aws --endpoint-url http://minio:9002 s3 cp file.txt s3://my-bucket/
```

## Troubleshooting

### OIDC Policy Error

MinIO requires a `policy` claim in the OIDC token. Configure in Authentik property mappings.

### Connection Refused

Ensure MinIO is running:
```bash
docker logs minio
curl http://localhost:9002/minio/health/live
```
