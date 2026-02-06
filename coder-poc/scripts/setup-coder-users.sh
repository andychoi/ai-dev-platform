#!/bin/bash
# =============================================================================
# Coder User Setup Script
# Creates sample users: admin, app-manager, contractors
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CODER_URL="${CODER_URL:-http://localhost:7080}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# =============================================================================
# Check Prerequisites
# =============================================================================

print_header "Coder User Setup"

log_info "Checking Coder availability..."
if ! curl -sf "${CODER_URL}/api/v2/buildinfo" > /dev/null 2>&1; then
    log_error "Coder is not accessible at ${CODER_URL}"
    exit 1
fi
log_success "Coder is accessible"

# =============================================================================
# Check for Coder CLI
# =============================================================================

if ! command -v coder &> /dev/null; then
    log_warn "Coder CLI not found on host"
    log_info "Using Docker container for CLI commands..."
    CODER_CMD="docker exec -it coder-server coder"
else
    CODER_CMD="coder"
fi

# =============================================================================
# First-Time Setup Instructions
# =============================================================================

print_header "First-Time Setup Required"

cat << 'EOF'
To set up Coder users, follow these steps:

╔═══════════════════════════════════════════════════════════════════╗
║  STEP 1: Create Admin User (First Time Only)                      ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                    ║
║  1. Open browser: https://host.docker.internal:7443                           ║
║  2. Create first admin account:                                   ║
║     - Username: admin                                             ║
║     - Email: admin@localhost                                      ║
║     - Password: Admin123!                                         ║
║                                                                    ║
╚═══════════════════════════════════════════════════════════════════╝

╔═══════════════════════════════════════════════════════════════════╗
║  STEP 2: Create Additional Users via Admin Panel                  ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                    ║
║  1. Login as admin at https://host.docker.internal:7443                       ║
║  2. Go to: Deployment → Users → Create User                       ║
║                                                                    ║
║  Create these users:                                              ║
║  ┌─────────────────────────────────────────────────────────────┐  ║
║  │ Username       │ Email                   │ Role              │  ║
║  ├─────────────────────────────────────────────────────────────┤  ║
║  │ admin          │ admin@localhost         │ Owner (Admin)     │  ║
║  │ app-manager    │ manager@localhost       │ Template Admin    │  ║
║  │ contractor1    │ contractor1@localhost   │ Member            │  ║
║  │ contractor2    │ contractor2@localhost   │ Member            │  ║
║  │ contractor3    │ contractor3@localhost   │ Member            │  ║
║  └─────────────────────────────────────────────────────────────┘  ║
║                                                                    ║
║  Suggested Passwords:                                             ║
║  - Admin: Admin123!                                               ║
║  - App Manager: Manager123!                                       ║
║  - Contractors: Contractor123!                                    ║
║                                                                    ║
╚═══════════════════════════════════════════════════════════════════╝

╔═══════════════════════════════════════════════════════════════════╗
║  STEP 3: Configure Roles & Groups                                 ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                    ║
║  Coder Role Hierarchy:                                            ║
║                                                                    ║
║  ┌─────────────────────────────────────────────────────────────┐  ║
║  │ Role            │ Capabilities                               │  ║
║  ├─────────────────────────────────────────────────────────────┤  ║
║  │ Owner           │ Full admin: users, templates, deployments │  ║
║  │ Template Admin  │ Create/edit templates, view all workspaces│  ║
║  │ Member          │ Create workspaces from templates          │  ║
║  │ Auditor         │ Read-only access to audit logs           │  ║
║  └─────────────────────────────────────────────────────────────┘  ║
║                                                                    ║
║  To assign roles:                                                 ║
║  1. Go to: Deployment → Users → [Select User]                    ║
║  2. Click "Edit" and assign appropriate role                     ║
║                                                                    ║
╚═══════════════════════════════════════════════════════════════════╝

EOF

# =============================================================================
# CLI Setup (if logged in)
# =============================================================================

print_header "CLI-Based User Creation (Optional)"

cat << 'EOF'
If you have CLI access with admin token, you can create users via API:

# Login to Coder CLI
coder login https://host.docker.internal:7443

# Create users (requires admin)
coder users create --email manager@localhost --username app-manager
coder users create --email contractor1@localhost --username contractor1
coder users create --email contractor2@localhost --username contractor2

# List users
coder users list

# Assign roles via REST API
curl -X PATCH "https://host.docker.internal:7443/api/v2/users/{user_id}/roles" \
  -H "Coder-Session-Token: YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"roles": ["template-admin"]}'

EOF

# =============================================================================
# Summary
# =============================================================================

print_header "User Matrix"

cat << 'EOF'
┌───────────────────────────────────────────────────────────────────────────┐
│                        CODER USER MATRIX                                   │
├─────────────┬──────────────────────┬──────────────────┬──────────────────┤
│ User        │ Role                 │ Can Do           │ Cannot Do        │
├─────────────┼──────────────────────┼──────────────────┼──────────────────┤
│ admin       │ Owner                │ Everything       │ -                │
├─────────────┼──────────────────────┼──────────────────┼──────────────────┤
│ app-manager │ Template Admin       │ • Manage templates│ • Manage users  │
│             │                      │ • View workspaces │ • System config │
│             │                      │ • Create workspaces│                │
├─────────────┼──────────────────────┼──────────────────┼──────────────────┤
│ contractor1 │ Member               │ • Create workspace│ • Edit templates│
│ contractor2 │                      │ • Own workspace   │ • View others   │
│ contractor3 │                      │ • Use terminal/IDE│ • Admin panel   │
└─────────────┴──────────────────────┴──────────────────┴──────────────────┘

Screen Differences:
- Admin: Full sidebar with Users, Templates, Audit, Deployment settings
- App Manager: Templates + limited admin views
- Contractor: Only "Workspaces" and "Templates" (create from) visible
EOF

echo ""
log_success "Setup instructions complete!"
echo ""
echo "Next: Open https://host.docker.internal:7443 and create users"
