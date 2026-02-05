-- =============================================================================
-- PostgreSQL Initialization Script
-- Creates databases and users for all platform services
-- =============================================================================

-- Create Coder database and user
CREATE USER coder WITH PASSWORD 'coder';
CREATE DATABASE coder OWNER coder;
GRANT ALL PRIVILEGES ON DATABASE coder TO coder;

-- Create Authentik database and user
CREATE USER authentik WITH PASSWORD 'authentik';
CREATE DATABASE authentik OWNER authentik;
GRANT ALL PRIVILEGES ON DATABASE authentik TO authentik;

-- Create Platform database and user (for centralized audit/analytics)
CREATE USER platform WITH PASSWORD 'platform';
CREATE DATABASE platform OWNER platform;
GRANT ALL PRIVILEGES ON DATABASE platform TO platform;

-- Create LiteLLM database and user (virtual keys, usage tracking, budgets)
CREATE USER litellm WITH PASSWORD 'litellm';
CREATE DATABASE litellm OWNER litellm;
GRANT ALL PRIVILEGES ON DATABASE litellm TO litellm;

-- Log successful initialization
DO $$
BEGIN
    RAISE NOTICE '===========================================';
    RAISE NOTICE 'PostgreSQL initialized with databases:';
    RAISE NOTICE '  - coder     (user: coder)';
    RAISE NOTICE '  - authentik (user: authentik)';
    RAISE NOTICE '  - platform  (user: platform)';
    RAISE NOTICE '  - litellm   (user: litellm)';
    RAISE NOTICE '===========================================';
END $$;
