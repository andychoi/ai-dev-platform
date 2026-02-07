# MinIO Storage - FAQ

Frequently asked questions about MinIO S3-compatible object storage in the Dev Platform.

## Table of Contents

1. [Overview](#1-overview)
2. [Workspace Storage vs MinIO](#2-workspace-storage-vs-minio)
3. [How MinIO is Allocated to Workspaces](#3-how-minio-is-allocated-to-workspaces)
4. [Sharing Data Between Users](#4-sharing-data-between-users)
5. [Access & Authentication](#5-access--authentication)
6. [Usage from Workspaces](#6-usage-from-workspaces)
7. [Bucket Management](#7-bucket-management)
8. [Security & Isolation](#8-security--isolation)
9. [Backup & Data Protection](#9-backup--data-protection)
10. [Production Considerations](#10-production-considerations)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Overview

### Q: What is MinIO?

**A:** MinIO is an S3-compatible object storage service deployed as part of the Dev Platform. It provides a shared storage layer for:
- Build artifacts and binaries
- Shared datasets and documentation
- Database backups (PostgreSQL dumps)
- File exchange between users (via shared buckets)

| Endpoint | URL (Host) | URL (from Workspace) | Purpose |
|----------|------------|----------------------|---------|
| Console UI | http://localhost:9001 | N/A (host only) | Web management |
| S3 API | http://localhost:9002 | http://minio:9002 | Programmatic access |
| Health | http://localhost:9002/minio/health/live | http://minio:9002/minio/health/live | Health check |

---

### Q: Is MinIO the same as workspace storage?

**A:** **No.** They are two separate systems:

| Feature | Workspace Storage (Docker Volume) | MinIO (Object Storage) |
|---------|-----------------------------------|------------------------|
| **Purpose** | Personal workspace files | Shared artifacts & data |
| **Type** | Block storage (filesystem) | Object storage (S3 API) |
| **Mounted at** | `/home/coder/` | Not mounted (accessed via API) |
| **Scope** | One workspace only | Shared across all workspaces |
| **Persistence** | Survives stop/start; lost on delete | Persists independently |
| **Size** | Configured per workspace (10-50 GB) | Shared pool (no per-user quota) |
| **Access method** | Normal file I/O | S3 API (aws cli, mc, boto3, etc.) |

---

## 2. Workspace Storage vs MinIO

### Q: What is the "Disk Size" parameter when creating a workspace?

**A:** The **Disk Size** parameter (10 GB / 20 GB / 50 GB) configures a **Docker volume** mounted at `/home/coder/`. This is your workspace's local persistent storage — it is NOT MinIO.

```
Workspace Creation Parameters:
┌──────────────────────────────────────────────────┐
│ CPU Cores:     2 cores / 4 cores                 │
│ Memory:        4 GB / 8 GB                       │
│ Disk Size:     10 GB / 20 GB / 50 GB  ← Docker  │  ← This is NOT MinIO
│ AI Provider:   Claude / Bedrock / Gemini         │
└──────────────────────────────────────────────────┘
```

**How it works internally:**
- Terraform creates a Docker volume: `coder-{username}-{workspace}-data`
- Mounted at `/home/coder/` in the workspace container
- Data survives workspace stop/start cycles
- Data is **destroyed** when workspace is deleted

### Q: When should I use workspace storage vs MinIO?

**A:**

| Use Case | Use Workspace Storage | Use MinIO |
|----------|-----------------------|-----------|
| Source code | Yes | No |
| IDE settings & extensions | Yes | No |
| Build outputs (temporary) | Yes | No |
| Build artifacts (to share) | No | Yes |
| Datasets (shared) | No | Yes |
| Database backups | No | Yes |
| Files to share with others | No | Yes |
| Documentation/assets | No | Yes |
| Personal project files | Yes | No |

---

## 3. How MinIO is Allocated to Workspaces

### Q: Is MinIO automatically provisioned per workspace?

**A:** **No.** MinIO is a **shared platform service**, not a per-workspace resource. The current PoC architecture works as follows:

```
┌─────────────────────────────────────────────────────────────┐
│                    MinIO Server                              │
│                  (Shared Instance)                           │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ bucket-1 │  │ bucket-2 │  │ shared   │  │ backups  │   │
│  │          │  │          │  │          │  │          │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
└──────────────────────────────────────────────────────────────┘
        ▲               ▲              ▲
        │               │              │
  ┌───────────┐  ┌───────────┐  ┌───────────┐
  │Workspace 1│  │Workspace 2│  │Workspace 3│
  │(user-A)   │  │(user-B)   │  │(user-A)   │
  └───────────┘  └───────────┘  └───────────┘
```

**Current behavior:**
- No automatic bucket creation when a workspace is provisioned
- No per-user or per-workspace bucket isolation
- All workspaces access MinIO using the same shared admin credentials
- Buckets must be created manually (via Console UI or CLI)

### Q: How do workspaces connect to MinIO?

**A:** Workspaces are on the same Docker network (`coder-network`) as MinIO, so they can reach it via internal DNS:

```
Host: minio
Port: 9002
Protocol: HTTP (no TLS in PoC)
```

No MinIO credentials are injected into workspaces automatically. Users must configure access manually or use the admin credentials.

---

## 4. Sharing Data Between Users

### Q: How can users share files with each other?

**A:** Since workspaces are isolated (users cannot access each other's workspaces), MinIO serves as the file sharing mechanism:

**Option 1: Shared Bucket**
```bash
# User A uploads
aws --endpoint-url http://minio:9002 s3 cp report.pdf s3://shared-files/reports/

# User B downloads
aws --endpoint-url http://minio:9002 s3 cp s3://shared-files/reports/report.pdf ./
```

**Option 2: Project-Specific Bucket**
```bash
# Create a project bucket
aws --endpoint-url http://minio:9002 s3 mb s3://project-alpha/

# Team members upload/download
aws --endpoint-url http://minio:9002 s3 sync ./build/ s3://project-alpha/builds/
```

**Option 3: Git (Recommended for code)**
- Push code to Gitea for sharing
- MinIO is better for large binary files, datasets, and artifacts

### Q: Can I restrict who sees which buckets?

**A:** In the current PoC, **no** — all users share the same admin credentials. For production, you would need:

1. **Per-user MinIO credentials** via OIDC/STS tokens
2. **Bucket policies** restricting access by user/group
3. **IAM policies** mapped to Authentik groups

See [Production Considerations](#10-production-considerations) for details.

### Q: Is there a size limit per user?

**A:** In the current PoC, **no per-user quota exists**. All users share the same MinIO storage pool. The total storage is limited by the Docker volume `minio_data` on the host machine.

---

## 5. Access & Authentication

### Q: What are the MinIO credentials?

**A:**

| Method | Username/Key | Password/Secret |
|--------|-------------|-----------------|
| Admin (Console) | `minioadmin` | `minioadmin` |
| Admin (S3 API) | `minioadmin` (Access Key) | `minioadmin` (Secret Key) |
| SSO (Console) | Click "Login with SSO" | Authentik credentials |

### Q: Can I login to MinIO Console with SSO?

**A:** Yes. MinIO is configured with OIDC via Authentik:

1. Go to http://localhost:9001
2. Click **"Login with SSO"**
3. Authenticate with Authentik credentials
4. You'll be logged in with permissions based on the `policy` claim

> Note: The OIDC `policy` claim must be configured in Authentik property mappings. Without it, SSO login will fail with a policy error.

### Q: How do I access MinIO from inside a workspace?

**A:** Use the S3 API endpoint with the internal DNS name:

```bash
# Set environment variables
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export AWS_ENDPOINT_URL=http://minio:9002

# Now use standard aws CLI commands
aws s3 ls
aws s3 mb s3://my-bucket
aws s3 cp file.txt s3://my-bucket/
```

---

## 6. Usage from Workspaces

### Q: What tools can I use to access MinIO?

**A:** Any S3-compatible tool works:

**AWS CLI (pre-installed):**
```bash
aws --endpoint-url http://minio:9002 s3 ls
aws --endpoint-url http://minio:9002 s3 cp file.txt s3://bucket/
aws --endpoint-url http://minio:9002 s3 sync ./dir/ s3://bucket/dir/
```

**MinIO Client (mc):**
```bash
# Install mc
curl -O https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc && sudo mv mc /usr/local/bin/

# Configure alias
mc alias set myminio http://minio:9002 minioadmin minioadmin

# Use
mc ls myminio
mc mb myminio/new-bucket
mc cp file.txt myminio/new-bucket/
```

**Python (boto3):**
```python
import boto3

s3 = boto3.client('s3',
    endpoint_url='http://minio:9002',
    aws_access_key_id='minioadmin',
    aws_secret_access_key='minioadmin'
)

# List buckets
for bucket in s3.list_buckets()['Buckets']:
    print(bucket['Name'])

# Upload file
s3.upload_file('report.pdf', 'my-bucket', 'reports/report.pdf')

# Download file
s3.download_file('my-bucket', 'reports/report.pdf', './report.pdf')
```

**Node.js (@aws-sdk/client-s3):**
```javascript
const { S3Client, ListBucketsCommand } = require("@aws-sdk/client-s3");

const client = new S3Client({
  endpoint: "http://minio:9002",
  region: "us-east-1",
  credentials: {
    accessKeyId: "minioadmin",
    secretAccessKey: "minioadmin",
  },
  forcePathStyle: true,
});

const { Buckets } = await client.send(new ListBucketsCommand({}));
console.log(Buckets);
```

### Q: Can I mount a MinIO bucket as a filesystem?

**A:** Not directly. MinIO is object storage (accessed via S3 API), not block storage. You could use tools like `s3fs-fuse` or `goofys`, but this is not recommended for the PoC due to performance and reliability concerns.

For filesystem-level persistence, use the workspace's Docker volume (`/home/coder/`).

---

## 7. Bucket Management

### Q: How do I create a bucket?

**A:** Three options:

**Console UI:**
1. Go to http://localhost:9001
2. Login as admin
3. Click **Buckets → Create Bucket**
4. Enter name, configure options
5. Click **Create**

**AWS CLI (from workspace):**
```bash
aws --endpoint-url http://minio:9002 s3 mb s3://my-new-bucket
```

**MinIO Client:**
```bash
mc mb myminio/my-new-bucket
```

### Q: What are bucket naming rules?

**A:**
- 3-63 characters
- Lowercase letters, numbers, hyphens only
- Must start with a letter or number
- No periods (affects SSL/TLS)
- Must be unique within the MinIO instance

### Q: How do I delete a bucket?

**A:**
```bash
# Must be empty first
aws --endpoint-url http://minio:9002 s3 rb s3://bucket-name

# Force delete (removes all objects first)
aws --endpoint-url http://minio:9002 s3 rb s3://bucket-name --force
```

> Warning: Deletion is permanent. There is no recycle bin.

### Q: Can I set object lifecycle rules (auto-delete)?

**A:** Yes, via the Console or `mc` CLI:

```bash
# Delete objects older than 30 days
mc ilm rule add myminio/temp-bucket --expire-days 30

# View current rules
mc ilm rule ls myminio/temp-bucket
```

---

## 8. Security & Isolation

### Q: Can users access each other's data in MinIO?

**A:** In the current PoC: **Yes**, because all workspaces use the same admin credentials. There is no per-user isolation.

**Production mitigation strategies:**

| Strategy | Description | Effort |
|----------|-------------|--------|
| **Bucket policies** | Restrict access per bucket by user/prefix | Medium |
| **OIDC STS tokens** | Temporary per-user credentials via Authentik | High |
| **Service accounts** | Per-workspace MinIO service accounts | Medium |
| **Naming convention** | `user-{username}/` prefix per user | Low (convention only) |

### Q: Are MinIO credentials exposed in workspace environment?

**A:** In the current PoC, MinIO credentials are **not automatically injected** into workspaces. Users must configure them manually. This means:
- No accidental credential exposure in logs
- Users must know the credentials to use MinIO
- But once shared, all users have the same access level

### Q: Is data encrypted?

**A:**

| Layer | PoC Status | Production Recommendation |
|-------|------------|---------------------------|
| In transit | No (HTTP) | Yes (HTTPS with TLS) |
| At rest | No | Yes (MinIO server-side encryption) |
| Client-side | No | Optional (encrypt before upload) |

---

## 9. Backup & Data Protection

### Q: Is MinIO data backed up?

**A:** MinIO data is stored in a Docker volume (`minio_data`). In the PoC:
- No automatic backups are configured
- Data persists across container restarts
- Data is lost if the Docker volume is deleted

### Q: How do I backup a bucket?

**A:**
```bash
# Mirror bucket to local directory
mc mirror myminio/important-bucket /backup/minio/important-bucket

# Sync to another S3 target
mc mirror myminio/important-bucket s3target/important-bucket
```

### Q: What is the recommended backup strategy?

**A:**

| Data Type | Frequency | Method | Destination |
|-----------|-----------|--------|-------------|
| Critical buckets | Daily | `mc mirror` | External storage |
| PostgreSQL dumps | Daily | `pg_dump` | MinIO bucket |
| Workspace volumes | On-demand | Volume snapshot | MinIO bucket |
| MinIO config | On change | Export policies | Git repository |

---

## 10. Production Considerations

### Q: What changes are needed for production?

**A:**

| Area | PoC (Current) | Production (Recommended) |
|------|---------------|--------------------------|
| **Deployment** | Single instance | Distributed (4+ nodes) |
| **Storage** | Docker volume | Dedicated disks / NAS |
| **Authentication** | Shared admin creds | OIDC STS per-user tokens |
| **Bucket isolation** | None | Per-user/project policies |
| **Encryption** | None | TLS + server-side encryption |
| **Quotas** | None | Per-bucket/user limits |
| **High availability** | None | Erasure coding + replication |
| **Monitoring** | Platform Admin dashboard | Prometheus + Grafana |
| **Backup** | Manual | Automated `mc mirror` + offsite |

### Q: How would per-user bucket provisioning work in production?

**A:** Recommended approach using OIDC STS (Security Token Service):

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Authentik   │────▶│  MinIO STS   │────▶│  Temp Creds  │
│  (OIDC Token) │     │  (Assume     │     │  (Scoped to  │
│               │     │   Role)      │     │   user path) │
└──────────────┘     └──────────────┘     └──────────────┘
                                                  │
                                                  ▼
                                          ┌──────────────┐
                                          │  MinIO API   │
                                          │  (User can   │
                                          │  only access │
                                          │  own prefix) │
                                          └──────────────┘
```

1. User authenticates via Authentik (OIDC)
2. Workspace requests STS temporary credentials from MinIO
3. Credentials are scoped to `user-{username}/*` prefix
4. User can only read/write their own data

### Q: How do I set up bucket policies for team sharing?

**A:** Example: Team-scoped bucket policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"AWS": ["arn:aws:iam:::user/contractor1"]},
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": ["arn:aws:s3:::project-alpha/*"]
    },
    {
      "Effect": "Deny",
      "Principal": {"AWS": ["arn:aws:iam:::user/contractor1"]},
      "Action": ["s3:DeleteBucket"],
      "Resource": ["arn:aws:s3:::project-alpha"]
    }
  ]
}
```

Apply:
```bash
mc admin policy create myminio project-alpha-rw policy.json
mc admin policy attach myminio project-alpha-rw --user contractor1
```

---

## 11. Troubleshooting

### Q: "Connection refused" when accessing MinIO from workspace

**A:** Check that MinIO is running and accessible:
```bash
# From workspace terminal
curl -s http://minio:9002/minio/health/live
# Should return: OK

# If it fails, check from host
docker logs minio
docker ps | grep minio
```

### Q: "Access Denied" when using S3 commands

**A:**
1. Verify credentials are correct:
   ```bash
   echo $AWS_ACCESS_KEY_ID    # Should be: minioadmin
   echo $AWS_SECRET_ACCESS_KEY # Should be: minioadmin
   ```
2. Verify endpoint URL:
   ```bash
   echo $AWS_ENDPOINT_URL     # Should be: http://minio:9002
   ```
3. Check if bucket exists:
   ```bash
   aws --endpoint-url http://minio:9002 s3 ls
   ```

### Q: OIDC login fails with "policy" error

**A:** MinIO requires a `policy` claim in the OIDC token. Fix in Authentik:

1. Go to Authentik Admin → Customization → Property Mappings
2. Create or edit the MinIO scope mapping
3. Ensure it includes a `policy` claim:
   ```python
   return {
       "policy": "readwrite",  # or "readonly", "consoleAdmin"
   }
   ```
4. Attach the mapping to the MinIO OIDC provider

### Q: Uploads are slow

**A:**
- PoC uses a single MinIO instance — performance is limited
- For large files, use multipart upload (automatic with `aws s3 cp` for files > 8 MB)
- Check network: workspace and MinIO are on the same Docker bridge network, so latency should be minimal
- Monitor disk I/O on the host machine

### Q: How do I check storage usage?

**A:**

**Platform Admin Dashboard:**
- Go to the Platform Admin UI (http://localhost:8080)
- Navigate to Storage section
- View per-bucket stats (objects, size)

**CLI:**
```bash
# List buckets with sizes
mc ls myminio --summarize

# Disk usage per bucket
mc du myminio/bucket-name
```

### Q: MinIO container keeps restarting

**A:**
```bash
# Check logs for errors
docker logs minio --tail 50

# Common causes:
# 1. Port conflict (9001 or 9002 already in use)
# 2. Volume permission issues
# 3. Insufficient disk space
df -h  # Check available disk space
```

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Workspace Container (contractor1)                                      │
│  ┌────────────────────────────────┐  ┌─────────────────────────────┐   │
│  │  /home/coder/  (Docker Volume) │  │  S3 API Client             │   │
│  │  ├── workspace/               │  │  (aws cli / boto3 / mc)    │   │
│  │  ├── .config/                 │  │  → http://minio:9002       │   │
│  │  └── ...                      │  └──────────────┬──────────────┘   │
│  │  LOCAL PERSISTENT STORAGE     │                 │                   │
│  └────────────────────────────────┘                 │                   │
└─────────────────────────────────────────────────────┼───────────────────┘
                                                      │ S3 Protocol
                                                      ▼
                                        ┌──────────────────────────┐
                                        │      MinIO Server        │
                                        │   (Shared Instance)      │
                                        │                          │
                                        │  Volume: minio_data      │
                                        │  API:    :9002            │
                                        │  Console: :9001           │
                                        │                          │
                                        │  ┌────────┐ ┌────────┐  │
                                        │  │bucket-1│ │bucket-2│  │
                                        │  └────────┘ └────────┘  │
                                        └──────────────────────────┘
```

**Key takeaway:** Workspace storage (Docker volume at `/home/coder/`) and MinIO are completely independent systems. The "Disk Size" workspace parameter controls the Docker volume, not MinIO.

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-05 | Platform Team | Initial version |
