-- Test Database Initialization Script
-- This creates sample tables and data for connectivity testing

-- Create schema for test data
CREATE SCHEMA IF NOT EXISTS app;

-- Sample users table
CREATE TABLE app.users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL,
    role VARCHAR(20) DEFAULT 'user',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Sample projects table
CREATE TABLE app.projects (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    owner_id INTEGER REFERENCES app.users(id),
    status VARCHAR(20) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Sample tasks table
CREATE TABLE app.tasks (
    id SERIAL PRIMARY KEY,
    project_id INTEGER REFERENCES app.projects(id),
    title VARCHAR(200) NOT NULL,
    description TEXT,
    assignee_id INTEGER REFERENCES app.users(id),
    status VARCHAR(20) DEFAULT 'pending',
    priority INTEGER DEFAULT 3,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample users
INSERT INTO app.users (username, email, role) VALUES
    ('admin', 'admin@company.internal', 'admin'),
    ('developer1', 'dev1@company.internal', 'developer'),
    ('developer2', 'dev2@company.internal', 'developer'),
    ('contractor1', 'contractor1@external.com', 'contractor'),
    ('contractor2', 'contractor2@external.com', 'contractor');

-- Insert sample projects
INSERT INTO app.projects (name, description, owner_id, status) VALUES
    ('Platform Core', 'Core platform services', 1, 'active'),
    ('API Gateway', 'API gateway implementation', 2, 'active'),
    ('Frontend App', 'Web frontend application', 3, 'active'),
    ('Mobile App', 'Mobile application', 2, 'planning');

-- Insert sample tasks
INSERT INTO app.tasks (project_id, title, description, assignee_id, status, priority) VALUES
    (1, 'Setup database schema', 'Design and implement database schema', 2, 'completed', 1),
    (1, 'Implement authentication', 'Add OAuth2 authentication', 4, 'in_progress', 1),
    (2, 'Rate limiting', 'Implement rate limiting middleware', 5, 'pending', 2),
    (2, 'Audit logging', 'Add request/response logging', 4, 'in_progress', 2),
    (3, 'Dashboard UI', 'Build main dashboard interface', 3, 'in_progress', 1),
    (3, 'User settings page', 'Create user settings page', 5, 'pending', 3);

-- Create read-only role for contractors
CREATE ROLE contractor_readonly;
GRANT USAGE ON SCHEMA app TO contractor_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA app TO contractor_readonly;

-- Create a contractor user with limited access
CREATE USER contractor WITH PASSWORD 'contractor123';
GRANT contractor_readonly TO contractor;

-- View for contractors (hides sensitive data)
CREATE VIEW app.my_tasks AS
SELECT
    t.id,
    t.title,
    t.description,
    t.status,
    t.priority,
    p.name as project_name,
    u.username as assignee
FROM app.tasks t
JOIN app.projects p ON t.project_id = p.id
LEFT JOIN app.users u ON t.assignee_id = u.id;

GRANT SELECT ON app.my_tasks TO contractor_readonly;

-- Log successful initialization
DO $$
BEGIN
    RAISE NOTICE 'Test database initialized successfully';
    RAISE NOTICE 'Connection info:';
    RAISE NOTICE '  Host: testdb';
    RAISE NOTICE '  Port: 5432';
    RAISE NOTICE '  Database: testapp';
    RAISE NOTICE '  Full access: appuser / testpassword';
    RAISE NOTICE '  Read-only: contractor / contractor123';
END $$;
