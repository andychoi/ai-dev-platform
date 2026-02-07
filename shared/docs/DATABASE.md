# Developer Database Guide

This guide explains how to use the developer database provisioning system in the Coder WebIDE platform.

## Overview

The platform provides automatic database provisioning for developers through the **DevDB** service. Databases can be:

- **Individual**: Personal database for each developer (`dev_{username}`)
- **Team**: Shared database for template/project teams (`team_{template_name}`)

```
┌─────────────────────────────────────────────────────────────────┐
│                    DevDB (PostgreSQL 17)                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Individual Databases          Team Databases                   │
│  ┌──────────────────┐         ┌──────────────────┐             │
│  │ dev_contractor1  │         │ team_frontend    │             │
│  │ Owner: c1 only   │         │ Shared by team   │             │
│  └──────────────────┘         └──────────────────┘             │
│  ┌──────────────────┐         ┌──────────────────┐             │
│  │ dev_contractor2  │         │ team_backend     │             │
│  │ Owner: c2 only   │         │ Shared by team   │             │
│  └──────────────────┘         └──────────────────┘             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Selecting Database Type

When creating a workspace, choose your database type:

| Type | Naming | Use Case |
|------|--------|----------|
| **Individual** | `dev_{username}` | Personal development, experiments, isolated work |
| **Team** | `team_{name}` | Shared project database, team collaboration |
| **None** | - | No database needed |

### Creating a Workspace with Database

**Via Web UI:**
1. Create new workspace
2. Under "Database Type", select:
   - "Individual" for personal database
   - "Team" for shared database (enter team name)
   - "None" to skip

**Via CLI:**
```bash
# Individual database
coder create my-workspace --template contractor-workspace \
  --parameter database_type=individual

# Team database
coder create my-workspace --template contractor-workspace \
  --parameter database_type=team \
  --parameter team_database_name=frontend-project
```

## Connecting to Your Database

### Environment Variables

After workspace starts, these variables are available:

```bash
# Check your database configuration
echo $DEVDB_HOST      # devdb
echo $DEVDB_PORT      # 5432
echo $DEVDB_NAME      # dev_contractor1 or team_frontend
echo $DEVDB_USER      # Your database user
echo $DEVDB_URL       # Full connection string (postgresql://user@devdb:5432/database)
```

### Using psql

```bash
# Connect using environment variables
psql -h $DEVDB_HOST -p $DEVDB_PORT -U $DEVDB_USER -d $DEVDB_NAME

# Or use the connection URL
psql $DEVDB_URL
```

### Using in Code

**Python (psycopg2):**
```python
import os
import psycopg2

conn = psycopg2.connect(os.environ['DEVDB_URL'])
# or
conn = psycopg2.connect(
    host=os.environ['DEVDB_HOST'],
    port=os.environ['DEVDB_PORT'],
    database=os.environ['DEVDB_NAME'],
    user=os.environ['DEVDB_USER']
)
```

**Node.js (pg):**
```javascript
const { Pool } = require('pg');
const pool = new Pool({
  connectionString: process.env.DEVDB_URL
});
```

**Java (JDBC):**
```java
String url = "jdbc:postgresql://" +
    System.getenv("DEVDB_HOST") + ":" +
    System.getenv("DEVDB_PORT") + "/" +
    System.getenv("DEVDB_NAME");
Connection conn = DriverManager.getConnection(url,
    System.getenv("DEVDB_USER"), "");
```

## Database Management

### Creating Tables

Individual databases give you full control:

```sql
-- Create your schema
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(255) UNIQUE,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE tasks (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    title VARCHAR(255),
    completed BOOLEAN DEFAULT FALSE
);
```

### Importing Data

```bash
# Import SQL file
psql $DEVDB_URL < schema.sql

# Import CSV
psql $DEVDB_URL -c "\copy users FROM 'users.csv' CSV HEADER"
```

### Exporting Data

```bash
# Export to SQL
pg_dump $DEVDB_URL > backup.sql

# Export specific table to CSV
psql $DEVDB_URL -c "\copy users TO 'users.csv' CSV HEADER"
```

## Team Database Best Practices

### Schema Organization

Use schemas to organize team database:

```sql
-- Each developer gets their own schema
CREATE SCHEMA IF NOT EXISTS dev_contractor1;
CREATE SCHEMA IF NOT EXISTS dev_contractor2;

-- Shared schema for production-like data
CREATE SCHEMA IF NOT EXISTS shared;
```

### Access Control

Team databases have shared access. Coordinate with your team:

```sql
-- Create team table in shared schema
CREATE TABLE shared.products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255),
    price DECIMAL(10,2)
);

-- Grant access (done by team lead)
GRANT ALL ON ALL TABLES IN SCHEMA shared TO team_frontend;
```

### Data Isolation

For sensitive testing, use personal schemas:

```sql
-- Work in your own schema
SET search_path TO dev_contractor1, shared, public;

-- Your tables won't conflict with others
CREATE TABLE experiments (
    id SERIAL PRIMARY KEY,
    data JSONB
);
```

## Useful Commands

### Check Database Info

```bash
# List all databases you have access to
psql -h devdb -U workspace_provisioner -d devdb -c \
  "SELECT * FROM provisioning.list_user_databases('$USER');"

# Check database size
psql $DEVDB_URL -c "SELECT pg_size_pretty(pg_database_size(current_database()));"
```

### PostgreSQL Tips

```sql
-- List all tables
\dt

-- Describe table structure
\d users

-- Show running queries
SELECT * FROM pg_stat_activity WHERE datname = current_database();

-- Check table sizes
SELECT relname, pg_size_pretty(pg_total_relation_size(relid))
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
```

## Troubleshooting

### Database Not Provisioned

If `$DEVDB_NAME` is empty:

1. Check workspace logs: Look for "DevDB not available"
2. Verify DevDB is running: `docker ps | grep devdb`
3. Restart workspace to retry provisioning

### Connection Refused

```bash
# Test connectivity
nc -zv devdb 5432

# Check if DevDB is healthy
docker exec devdb pg_isready -U devdb_admin
```

### Permission Denied

For team databases:
1. Verify you have access: Check with team lead
2. Request access via admin

For individual databases:
1. Database may have been created with different credentials
2. Contact platform admin to reset

### Slow Queries

```sql
-- Enable query timing
\timing on

-- Check for missing indexes
EXPLAIN ANALYZE SELECT * FROM large_table WHERE column = 'value';

-- Find slow queries
SELECT query, calls, mean_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;
```

## Database vs TestDB

The platform has two PostgreSQL instances:

| Feature | DevDB | TestDB |
|---------|-------|--------|
| Purpose | Developer databases | Integration testing |
| Databases | Multiple (per user/team) | Single (testapp) |
| Access | Full control | Read-only for contractors |
| Data | Your data | Sample app data |
| Use for | Development | Testing connectivity |

### TestDB Connection Details

```bash
# TestDB connection info
Host:     testdb
Port:     5432
Database: testapp

# Full access (admin)
User:     appuser
Password: testpassword

# Read-only access (contractors)
User:     contractor
Password: contractor123
```

### TestDB Schema

TestDB contains sample application data in the `app` schema:

| Table/View | Description |
|------------|-------------|
| `app.users` | Sample users (admin, developers, contractors) |
| `app.projects` | Sample projects with ownership |
| `app.tasks` | Tasks linked to projects and assignees |
| `app.my_tasks` | View joining tasks with project and user info |

**When to use DevDB:**
- Your application needs a database
- You need full DDL/DML access
- Personal or team development

**When to use TestDB:**
- Testing database connectivity
- Learning SQL with sample data
- Read-only queries

## Security Notes

### Trust-Based Authentication

DevDB uses **trust-based authentication** for the internal Docker network:

- **No passwords required** - Connections from workspaces are trusted
- **Internal network only** - DevDB is not exposed to the internet
- **User isolation** - Each user has their own database user/role
- **Audit trail** - All database access is logged

This is secure because:
1. DevDB only accepts connections from the internal Docker network
2. Workspaces are already authenticated via Coder
3. Individual databases are owned by specific users
4. No external access is possible

### Database Isolation

| Database Type | Access Control |
|---------------|----------------|
| Individual (`dev_*`) | Only the owner can access |
| Team (`team_*`) | All template users can access |

### Connection Security

```
Workspace → Docker Network (internal) → DevDB
    ↑              ↑                       ↑
 Authenticated   Isolated              Trust auth
 via Coder       network               (no password)
```

## Admin Guide

### Admin Management Tool

Use the `manage-devdb.sh` script for database administration:

```bash
# List all databases
./scripts/manage-devdb.sh list

# Show summary statistics
./scripts/manage-devdb.sh summary

# Inspect specific database
./scripts/manage-devdb.sh inspect dev_contractor1

# List all users and their access
./scripts/manage-devdb.sh users

# Find orphaned databases (workspace deleted)
./scripts/manage-devdb.sh orphans

# Cleanup orphans (dry-run first)
./scripts/manage-devdb.sh cleanup --dry-run
./scripts/manage-devdb.sh cleanup

# Delete specific database
./scripts/manage-devdb.sh delete dev_olduser

# Show database sizes
./scripts/manage-devdb.sh size

# Show active connections
./scripts/manage-devdb.sh connections

# Create team database
./scripts/manage-devdb.sh create-team frontend-project
```

### Identifying Orphaned Databases

Orphaned databases occur when:
- Workspace is deleted but database remains
- User account is removed
- Template is deactivated

The `orphans` command checks:
1. Databases without associated active workspaces
2. Databases not accessed in 30+ days

```bash
# Find orphans
./scripts/manage-devdb.sh orphans

# Example output:
# Database          Owner         Workspace ID   Last Access  Status
# dev_oldcontractor contractor99  ws-abc123      2024-01-15   Workspace deleted
# dev_testuser      testuser      (null)         2024-02-01   No workspace ID
```

### Cleanup Policy

Recommended cleanup policy:
- **30 days**: Warning notification to admin
- **60 days**: Review and contact user if possible
- **90 days**: Eligible for automatic cleanup

```bash
# Preview what would be deleted (>90 days inactive)
./scripts/manage-devdb.sh cleanup --dry-run

# Actually cleanup
./scripts/manage-devdb.sh cleanup
```

### Creating Team Databases

Pre-create team databases for projects:

```bash
# Via admin script
./scripts/manage-devdb.sh create-team frontend-project
./scripts/manage-devdb.sh create-team backend-api
./scripts/manage-devdb.sh create-team data-analytics

# Or via SQL
docker exec devdb psql -U devdb_admin -d devdb -c \
  "SELECT * FROM provisioning.create_team_db('project-alpha');"
```

### Monitoring

```bash
# Database sizes (identify large databases)
./scripts/manage-devdb.sh size

# Active connections (troubleshoot issues)
./scripts/manage-devdb.sh connections

# Full summary
./scripts/manage-devdb.sh summary
```

### Direct SQL Access (Advanced)

```bash
# Connect as admin
docker exec -it devdb psql -U devdb_admin -d devdb

# Useful queries:
# View all provisioned databases
SELECT * FROM provisioning.active_databases;

# Check database summary
SELECT * FROM provisioning.database_summary;

# Find databases by owner
SELECT * FROM provisioning.databases WHERE owner_username = 'contractor1';

# Check user access
SELECT * FROM provisioning.db_users WHERE username = 'contractor1';
```

## Quick Reference

```
┌────────────────────────────────────────────────────────────────┐
│                    DATABASE QUICK REFERENCE                     │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ENVIRONMENT VARIABLES                                         │
│  ─────────────────────                                         │
│  DEVDB_HOST      Database server (devdb)                       │
│  DEVDB_PORT      Database port (5432)                          │
│  DEVDB_NAME      Your database name                            │
│  DEVDB_USER      Your database user                            │
│  DEVDB_URL       Full connection string                        │
│                                                                 │
│  COMMON COMMANDS                                               │
│  ───────────────                                               │
│  psql $DEVDB_URL              Connect to database              │
│  \dt                          List tables                      │
│  \d tablename                 Describe table                   │
│  \q                           Quit psql                        │
│                                                                 │
│  CONNECTION STRING FORMAT                                      │
│  ────────────────────────                                      │
│  postgresql://user@devdb:5432/database                         │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```
