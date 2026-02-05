#!/bin/bash
# =============================================================================
# Setup Template Requests Repository in Gitea
# Creates a repo for workspace template requests with issue templates
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
GITEA_URL="${GITEA_URL:-http://localhost:3000}"
GITEA_ADMIN="${GITEA_ADMIN:-gitea}"
GITEA_PASSWORD="${GITEA_PASSWORD:-admin123}"
REPO_NAME="template-requests"
REPO_DESC="Workspace Template Requests and Issues"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/../gitea/issue-templates"
TEMP_DIR="/tmp/template-requests-$$"

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

print_header "Setting Up Template Requests Repository"

log_info "Checking Gitea availability..."
if ! curl -sf "${GITEA_URL}/" > /dev/null 2>&1; then
    log_error "Gitea is not accessible at ${GITEA_URL}"
    exit 1
fi
log_success "Gitea is accessible"

# =============================================================================
# Create Repository via API
# =============================================================================

log_info "Creating repository: ${REPO_NAME}"

# Check if repo already exists
REPO_EXISTS=$(curl -sf -u "${GITEA_ADMIN}:${GITEA_PASSWORD}" \
    "${GITEA_URL}/api/v1/repos/${GITEA_ADMIN}/${REPO_NAME}" 2>/dev/null | grep -c "id" || echo "0")

if [ "$REPO_EXISTS" -gt 0 ]; then
    log_warn "Repository already exists, updating content..."
else
    # Create the repository
    CREATE_RESPONSE=$(curl -sf -X POST \
        -u "${GITEA_ADMIN}:${GITEA_PASSWORD}" \
        -H "Content-Type: application/json" \
        "${GITEA_URL}/api/v1/user/repos" \
        -d "{
            \"name\": \"${REPO_NAME}\",
            \"description\": \"${REPO_DESC}\",
            \"private\": false,
            \"auto_init\": true,
            \"readme\": \"Default\"
        }" 2>&1 || echo "error")

    if echo "$CREATE_RESPONSE" | grep -q "error\|already exist"; then
        log_warn "Repository may already exist or creation had issues"
    else
        log_success "Repository created"
    fi
fi

# =============================================================================
# Clone and Add Issue Templates
# =============================================================================

log_info "Setting up repository content..."

# Create temp directory
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Clone the repo
git clone "http://${GITEA_ADMIN}:${GITEA_PASSWORD}@localhost:3000/${GITEA_ADMIN}/${REPO_NAME}.git" repo 2>/dev/null || {
    log_warn "Clone failed, initializing new repo"
    mkdir repo
    cd repo
    git init
    git remote add origin "http://${GITEA_ADMIN}:${GITEA_PASSWORD}@localhost:3000/${GITEA_ADMIN}/${REPO_NAME}.git"
    cd ..
}

cd repo

# Configure git
git config user.email "admin@localhost"
git config user.name "Platform Admin"

# Create directory structure
mkdir -p .gitea/issue_template

# Copy issue templates
if [ -d "$TEMPLATE_DIR" ]; then
    cp "$TEMPLATE_DIR"/*.md .gitea/issue_template/ 2>/dev/null || true
    log_success "Issue templates copied"
else
    log_warn "Issue templates directory not found: $TEMPLATE_DIR"
fi

# Create README
cat > README.md << 'EOF'
# Workspace Template Requests

This repository is used for requesting new workspace templates or reporting issues with existing templates.

## How to Submit a Request

### New Template Request
1. Go to [Issues](../../issues)
2. Click "New Issue"
3. Select "Workspace Template Request" template
4. Fill out all required fields
5. Submit the issue

### Report Template Issue
1. Go to [Issues](../../issues)
2. Click "New Issue"
3. Select "Template Issue Report" template
4. Provide details about the problem
5. Submit the issue

## Available Templates

| Template | Description | Status |
|----------|-------------|--------|
| contractor-workspace | Standard contractor development environment | Active |

## Request Process

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌──────────┐
│   Submit    │───>│   Review     │───>│   Build     │───>│  Deploy  │
│   Request   │    │   & Approve  │    │   Template  │    │  & Test  │
└─────────────┘    └──────────────┘    └─────────────┘    └──────────┘
```

1. **Submit Request**: User creates issue with requirements
2. **Review & Approve**: Platform team reviews and approves/rejects
3. **Build Template**: Approved templates are developed
4. **Deploy & Test**: Template is deployed and tested

## SLA

| Request Type | Target Response | Target Completion |
|--------------|-----------------|-------------------|
| Bug Fix | 1 business day | 3 business days |
| Minor Change | 2 business days | 5 business days |
| New Template | 3 business days | 10 business days |

## Contact

For urgent requests, contact the Platform Team:
- Email: platform-team@company.com
- Slack: #dev-platform

## Labels

| Label | Description |
|-------|-------------|
| `template-request` | New template request |
| `template-bug` | Bug in existing template |
| `pending-review` | Awaiting review |
| `approved` | Request approved |
| `in-progress` | Being worked on |
| `completed` | Request completed |
EOF

# Create ISSUE_TEMPLATE config
cat > .gitea/issue_template/config.yml << 'EOF'
blank_issues_enabled: false
contact_links:
  - name: Platform Team Documentation
    url: http://localhost:7080/docs
    about: View workspace template documentation
EOF

# Commit and push
git add -A
git commit -m "Setup template requests repository with issue templates" 2>/dev/null || {
    log_info "No changes to commit"
}

git push -u origin main 2>/dev/null || git push -u origin master 2>/dev/null || {
    log_warn "Push failed - repo may need manual setup"
}

# Cleanup
cd /
rm -rf "$TEMP_DIR"

# =============================================================================
# Summary
# =============================================================================

print_header "Setup Complete"

echo -e "${GREEN}Template Requests repository is ready!${NC}"
echo ""
echo "Repository URL: ${GITEA_URL}/${GITEA_ADMIN}/${REPO_NAME}"
echo ""
echo "Issue Templates:"
echo "  - Workspace Template Request"
echo "  - Template Issue Report"
echo ""
echo "Next Steps:"
echo "  1. Access Gitea: ${GITEA_URL}"
echo "  2. Login as: ${GITEA_ADMIN}"
echo "  3. Navigate to: ${REPO_NAME} repository"
echo "  4. Create issues using the templates"
echo ""
log_success "Setup completed successfully!"
