-- =============================================================================
-- Developer Database Server - Initialization Script
-- Provides individual and team databases for workspace development
-- =============================================================================

-- Create extension for UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- PROVISIONING SCHEMA
-- Stores metadata about provisioned databases
-- =============================================================================
CREATE SCHEMA IF NOT EXISTS provisioning;

-- Track all provisioned databases
CREATE TABLE IF NOT EXISTS provisioning.databases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    db_name VARCHAR(128) UNIQUE NOT NULL,
    db_type VARCHAR(20) NOT NULL CHECK (db_type IN ('individual', 'team')),
    owner_username VARCHAR(64),
    template_name VARCHAR(64),
    workspace_id VARCHAR(64),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_accessed TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Track database users
CREATE TABLE IF NOT EXISTS provisioning.db_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(64) NOT NULL,
    db_name VARCHAR(128) NOT NULL REFERENCES provisioning.databases(db_name) ON DELETE CASCADE,
    access_level VARCHAR(20) NOT NULL CHECK (access_level IN ('owner', 'write', 'read')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(username, db_name)
);

-- =============================================================================
-- DATABASE PROVISIONING FUNCTIONS
-- =============================================================================

-- Function to create an individual developer database
-- Note: Uses trust-based auth for internal network (no password required)
CREATE OR REPLACE FUNCTION provisioning.create_individual_db(
    p_username VARCHAR(64),
    p_workspace_id VARCHAR(64) DEFAULT NULL
) RETURNS TABLE(db_name VARCHAR, db_user VARCHAR, db_password VARCHAR) AS $$
DECLARE
    v_db_name VARCHAR(128);
    v_db_user VARCHAR(64);
BEGIN
    -- Generate database name: dev_{username}
    v_db_name := 'dev_' || lower(regexp_replace(p_username, '[^a-zA-Z0-9]', '_', 'g'));
    v_db_user := v_db_name;

    -- Check if database already exists
    IF EXISTS (SELECT 1 FROM pg_database WHERE datname = v_db_name) THEN
        -- Database exists, just return connection info
        -- Update last accessed time
        UPDATE provisioning.databases
        SET last_accessed = CURRENT_TIMESTAMP,
            workspace_id = COALESCE(p_workspace_id, workspace_id)
        WHERE db_name = v_db_name;

        -- Return existing info (no password needed - trust auth)
        RETURN QUERY SELECT v_db_name::VARCHAR, v_db_user::VARCHAR, ''::VARCHAR;
        RETURN;
    END IF;

    -- Create the database
    EXECUTE format('CREATE DATABASE %I OWNER devdb_admin', v_db_name);

    -- Create dedicated user for this database (no password - trust auth for internal network)
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_db_user) THEN
        EXECUTE format('CREATE USER %I', v_db_user);
    END IF;
    EXECUTE format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', v_db_name, v_db_user);

    -- Record in provisioning table
    INSERT INTO provisioning.databases (db_name, db_type, owner_username, workspace_id)
    VALUES (v_db_name, 'individual', p_username, p_workspace_id);

    INSERT INTO provisioning.db_users (username, db_name, access_level)
    VALUES (p_username, v_db_name, 'owner');

    -- Return connection info (no password for trust auth)
    RETURN QUERY SELECT v_db_name::VARCHAR, v_db_user::VARCHAR, ''::VARCHAR;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to create a team/shared database
-- Note: Uses trust-based auth for internal network (no password required)
CREATE OR REPLACE FUNCTION provisioning.create_team_db(
    p_template_name VARCHAR(64),
    p_owner_username VARCHAR(64) DEFAULT NULL
) RETURNS TABLE(db_name VARCHAR, db_user VARCHAR, db_password VARCHAR) AS $$
DECLARE
    v_db_name VARCHAR(128);
    v_db_user VARCHAR(64);
BEGIN
    -- Generate database name: team_{template_name}
    v_db_name := 'team_' || lower(regexp_replace(p_template_name, '[^a-zA-Z0-9]', '_', 'g'));
    v_db_user := v_db_name;

    -- Check if database already exists
    IF EXISTS (SELECT 1 FROM pg_database WHERE datname = v_db_name) THEN
        -- Database exists, return connection info
        UPDATE provisioning.databases
        SET last_accessed = CURRENT_TIMESTAMP
        WHERE db_name = v_db_name;

        RETURN QUERY SELECT v_db_name::VARCHAR, v_db_user::VARCHAR, ''::VARCHAR;
        RETURN;
    END IF;

    -- Create the database
    EXECUTE format('CREATE DATABASE %I OWNER devdb_admin', v_db_name);

    -- Create dedicated user for this database (no password - trust auth)
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_db_user) THEN
        EXECUTE format('CREATE USER %I', v_db_user);
    END IF;
    EXECUTE format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', v_db_name, v_db_user);

    -- Record in provisioning table
    INSERT INTO provisioning.databases (db_name, db_type, template_name, owner_username)
    VALUES (v_db_name, 'team', p_template_name, p_owner_username);

    IF p_owner_username IS NOT NULL THEN
        INSERT INTO provisioning.db_users (username, db_name, access_level)
        VALUES (p_owner_username, v_db_name, 'owner');
    END IF;

    -- Return connection info (no password for trust auth)
    RETURN QUERY SELECT v_db_name::VARCHAR, v_db_user::VARCHAR, ''::VARCHAR;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to grant user access to a team database
CREATE OR REPLACE FUNCTION provisioning.grant_team_access(
    p_username VARCHAR(64),
    p_db_name VARCHAR(128),
    p_access_level VARCHAR(20) DEFAULT 'write'
) RETURNS BOOLEAN AS $$
DECLARE
    v_db_user VARCHAR(64);
BEGIN
    -- Verify database exists and is a team database
    IF NOT EXISTS (
        SELECT 1 FROM provisioning.databases
        WHERE db_name = p_db_name AND db_type = 'team'
    ) THEN
        RAISE EXCEPTION 'Team database % not found', p_db_name;
    END IF;

    -- Create user-specific login if doesn't exist
    v_db_user := lower(regexp_replace(p_username, '[^a-zA-Z0-9]', '_', 'g'));

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_db_user) THEN
        EXECUTE format('CREATE USER %I WITH PASSWORD %L',
            v_db_user, encode(gen_random_bytes(16), 'hex'));
    END IF;

    -- Grant appropriate access
    IF p_access_level = 'read' THEN
        EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', p_db_name, v_db_user);
        -- Note: GRANT SELECT on tables must be done within the target database
    ELSE
        EXECUTE format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', p_db_name, v_db_user);
    END IF;

    -- Record access grant
    INSERT INTO provisioning.db_users (username, db_name, access_level)
    VALUES (p_username, p_db_name, p_access_level)
    ON CONFLICT (username, db_name)
    DO UPDATE SET access_level = p_access_level;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to list databases for a user
CREATE OR REPLACE FUNCTION provisioning.list_user_databases(
    p_username VARCHAR(64)
) RETURNS TABLE(
    db_name VARCHAR,
    db_type VARCHAR,
    access_level VARCHAR,
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        d.db_name::VARCHAR,
        d.db_type::VARCHAR,
        u.access_level::VARCHAR,
        d.created_at
    FROM provisioning.databases d
    JOIN provisioning.db_users u ON d.db_name = u.db_name
    WHERE u.username = p_username
    ORDER BY d.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get connection info
CREATE OR REPLACE FUNCTION provisioning.get_connection_info(
    p_db_name VARCHAR(128)
) RETURNS TABLE(
    host VARCHAR,
    port INTEGER,
    database_name VARCHAR,
    db_type VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        'devdb'::VARCHAR as host,
        5432::INTEGER as port,
        d.db_name::VARCHAR as database_name,
        d.db_type::VARCHAR
    FROM provisioning.databases d
    WHERE d.db_name = p_db_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- WORKSPACE PROVISIONER ROLE
-- Used by workspace startup scripts to provision databases
-- =============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'workspace_provisioner') THEN
        CREATE ROLE workspace_provisioner WITH LOGIN PASSWORD 'provisioner123';
    END IF;
END $$;

GRANT USAGE ON SCHEMA provisioning TO workspace_provisioner;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA provisioning TO workspace_provisioner;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA provisioning TO workspace_provisioner;

-- =============================================================================
-- SAMPLE TEAM DATABASES
-- Pre-create some team databases for testing
-- =============================================================================

-- These will be created on first workspace start that requests them
-- Example: SELECT * FROM provisioning.create_team_db('frontend-team');
-- Example: SELECT * FROM provisioning.create_team_db('backend-team');

-- =============================================================================
-- UTILITY VIEWS
-- =============================================================================
CREATE OR REPLACE VIEW provisioning.database_summary AS
SELECT
    db_type,
    COUNT(*) as count,
    MAX(created_at) as latest_created,
    MAX(last_accessed) as latest_accessed
FROM provisioning.databases
GROUP BY db_type;

CREATE OR REPLACE VIEW provisioning.active_databases AS
SELECT
    d.*,
    (SELECT COUNT(*) FROM provisioning.db_users u WHERE u.db_name = d.db_name) as user_count
FROM provisioning.databases d
WHERE d.last_accessed > CURRENT_TIMESTAMP - INTERVAL '30 days'
ORDER BY d.last_accessed DESC;

GRANT SELECT ON provisioning.database_summary TO workspace_provisioner;
GRANT SELECT ON provisioning.active_databases TO workspace_provisioner;

-- =============================================================================
-- AI USAGE TRACKING SCHEMA
-- Tracks AI API usage by user, workspace, template, and provider
-- =============================================================================

CREATE TABLE IF NOT EXISTS provisioning.ai_usage (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    -- Identity dimensions
    workspace_id VARCHAR(64),
    user_id VARCHAR(64),
    template_name VARCHAR(64),
    -- Provider dimensions
    provider VARCHAR(32) NOT NULL,  -- anthropic, bedrock, gemini
    model VARCHAR(64) NOT NULL,
    -- Metrics
    tokens_in INTEGER NOT NULL DEFAULT 0,
    tokens_out INTEGER NOT NULL DEFAULT 0,
    latency_ms INTEGER,
    status_code INTEGER,
    -- Request metadata
    endpoint VARCHAR(128),
    request_id VARCHAR(64)
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_ai_usage_timestamp ON provisioning.ai_usage(timestamp);
CREATE INDEX IF NOT EXISTS idx_ai_usage_user ON provisioning.ai_usage(user_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_ai_usage_workspace ON provisioning.ai_usage(workspace_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_ai_usage_template ON provisioning.ai_usage(template_name, timestamp);
CREATE INDEX IF NOT EXISTS idx_ai_usage_provider ON provisioning.ai_usage(provider, timestamp);

-- Composite index for common dashboard queries
CREATE INDEX IF NOT EXISTS idx_ai_usage_time_dims
ON provisioning.ai_usage(timestamp, provider, user_id, workspace_id);

-- =============================================================================
-- AI USAGE AGGREGATION VIEWS
-- Pre-computed views for dashboard queries
-- =============================================================================

-- Daily usage summary
CREATE OR REPLACE VIEW provisioning.ai_usage_daily AS
SELECT
    DATE(timestamp) as date,
    provider,
    user_id,
    workspace_id,
    template_name,
    COUNT(*) as request_count,
    SUM(tokens_in) as total_tokens_in,
    SUM(tokens_out) as total_tokens_out,
    SUM(tokens_in + tokens_out) as total_tokens,
    AVG(latency_ms)::INTEGER as avg_latency_ms,
    COUNT(CASE WHEN status_code >= 400 THEN 1 END) as error_count
FROM provisioning.ai_usage
GROUP BY DATE(timestamp), provider, user_id, workspace_id, template_name;

-- Weekly usage by provider
CREATE OR REPLACE VIEW provisioning.ai_usage_weekly_by_provider AS
SELECT
    DATE_TRUNC('week', timestamp)::DATE as week_start,
    provider,
    COUNT(*) as request_count,
    SUM(tokens_in) as total_tokens_in,
    SUM(tokens_out) as total_tokens_out,
    COUNT(DISTINCT user_id) as unique_users,
    COUNT(DISTINCT workspace_id) as unique_workspaces
FROM provisioning.ai_usage
GROUP BY DATE_TRUNC('week', timestamp), provider
ORDER BY week_start DESC, provider;

-- Weekly usage by user
CREATE OR REPLACE VIEW provisioning.ai_usage_weekly_by_user AS
SELECT
    DATE_TRUNC('week', timestamp)::DATE as week_start,
    user_id,
    COUNT(*) as request_count,
    SUM(tokens_in) as total_tokens_in,
    SUM(tokens_out) as total_tokens_out,
    ARRAY_AGG(DISTINCT provider) as providers_used,
    ARRAY_AGG(DISTINCT model) as models_used
FROM provisioning.ai_usage
WHERE user_id IS NOT NULL
GROUP BY DATE_TRUNC('week', timestamp), user_id
ORDER BY week_start DESC, total_tokens_out DESC;

-- Weekly usage by template
CREATE OR REPLACE VIEW provisioning.ai_usage_weekly_by_template AS
SELECT
    DATE_TRUNC('week', timestamp)::DATE as week_start,
    COALESCE(template_name, 'unknown') as template_name,
    COUNT(*) as request_count,
    SUM(tokens_in) as total_tokens_in,
    SUM(tokens_out) as total_tokens_out,
    COUNT(DISTINCT user_id) as unique_users
FROM provisioning.ai_usage
GROUP BY DATE_TRUNC('week', timestamp), template_name
ORDER BY week_start DESC, total_tokens_out DESC;

-- Usage summary for the current week
CREATE OR REPLACE VIEW provisioning.ai_usage_current_week AS
SELECT
    provider,
    user_id,
    workspace_id,
    template_name,
    COUNT(*) as request_count,
    SUM(tokens_in) as tokens_in,
    SUM(tokens_out) as tokens_out
FROM provisioning.ai_usage
WHERE timestamp >= DATE_TRUNC('week', CURRENT_TIMESTAMP)
GROUP BY provider, user_id, workspace_id, template_name;

-- Grant access to workspace provisioner and create ai_gateway role
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ai_gateway') THEN
        CREATE ROLE ai_gateway WITH LOGIN PASSWORD 'aigateway123';
    END IF;
END $$;

GRANT USAGE ON SCHEMA provisioning TO ai_gateway;
GRANT INSERT ON provisioning.ai_usage TO ai_gateway;
GRANT SELECT ON provisioning.ai_usage TO ai_gateway;
GRANT SELECT ON provisioning.ai_usage_daily TO ai_gateway;
GRANT SELECT ON provisioning.ai_usage_weekly_by_provider TO ai_gateway;
GRANT SELECT ON provisioning.ai_usage_weekly_by_user TO ai_gateway;
GRANT SELECT ON provisioning.ai_usage_weekly_by_template TO ai_gateway;
GRANT SELECT ON provisioning.ai_usage_current_week TO ai_gateway;

-- Also grant to workspace_provisioner for admin dashboard queries
GRANT SELECT ON provisioning.ai_usage TO workspace_provisioner;
GRANT SELECT ON provisioning.ai_usage_daily TO workspace_provisioner;
GRANT SELECT ON provisioning.ai_usage_weekly_by_provider TO workspace_provisioner;
GRANT SELECT ON provisioning.ai_usage_weekly_by_user TO workspace_provisioner;
GRANT SELECT ON provisioning.ai_usage_weekly_by_template TO workspace_provisioner;
GRANT SELECT ON provisioning.ai_usage_current_week TO workspace_provisioner;

-- Log initialization
DO $$
BEGIN
    RAISE NOTICE 'DevDB initialized successfully';
    RAISE NOTICE 'Use provisioning.create_individual_db(username) for individual databases';
    RAISE NOTICE 'Use provisioning.create_team_db(template_name) for team databases';
    RAISE NOTICE 'AI usage tracking table and views created';
END $$;
