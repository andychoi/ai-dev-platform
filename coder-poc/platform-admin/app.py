"""
Platform Admin Dashboard
Unified administration interface for the Coder WebIDE Platform
- Service health monitoring
- Developer database management
- User management with activity tracking
- Workspace overview with resource metrics
- AI usage tracking
"""

import json
import os
import math
import psycopg2
import psycopg2.extras
import requests
from flask import Flask, render_template, jsonify, request, redirect, url_for, flash, session
from datetime import datetime, timedelta
from functools import wraps
from concurrent.futures import ThreadPoolExecutor, as_completed
from minio import Minio
from minio.error import S3Error
from authlib.integrations.flask_client import OAuth

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'platform-admin-secret-key-change-me')

# =============================================================================
# OIDC Configuration
# =============================================================================
OIDC_ENABLED = os.environ.get('OIDC_ENABLED', 'true').lower() == 'true'
OIDC_ISSUER_URL = os.environ.get('OIDC_ISSUER_URL', 'http://authentik-server:9000/application/o/platform-admin/')
OIDC_CLIENT_ID = os.environ.get('OIDC_CLIENT_ID', 'platform-admin')
OIDC_CLIENT_SECRET = os.environ.get('OIDC_CLIENT_SECRET', '')

# Initialize OAuth
oauth = OAuth(app)
if OIDC_ENABLED and OIDC_CLIENT_SECRET:
    oauth.register(
        name='authentik',
        client_id=OIDC_CLIENT_ID,
        client_secret=OIDC_CLIENT_SECRET,
        server_metadata_url=f'{OIDC_ISSUER_URL}.well-known/openid-configuration',
        client_kwargs={
            'scope': 'openid profile email'
        }
    )


# =============================================================================
# Pagination Helper
# =============================================================================

class Pagination:
    """Helper class for pagination"""
    def __init__(self, page, per_page, total, items):
        self.page = page
        self.per_page = per_page
        self.total = total
        self.items = items

    @property
    def pages(self):
        return max(1, math.ceil(self.total / self.per_page))

    @property
    def has_prev(self):
        return self.page > 1

    @property
    def has_next(self):
        return self.page < self.pages

    @property
    def prev_num(self):
        return self.page - 1 if self.has_prev else None

    @property
    def next_num(self):
        return self.page + 1 if self.has_next else None

    def iter_pages(self, left_edge=2, right_edge=2, left_current=2, right_current=2):
        """Generate page numbers for pagination UI"""
        last = 0
        for num in range(1, self.pages + 1):
            if (num <= left_edge or
                (self.page - left_current <= num <= self.page + right_current) or
                num > self.pages - right_edge):
                if last + 1 != num:
                    yield None  # Gap indicator
                yield num
                last = num


def get_pagination_args():
    """Extract pagination args from request"""
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 25, type=int)
    per_page = min(per_page, 100)  # Max 100 per page
    search = request.args.get('search', '').strip()
    status_filter = request.args.get('status', '')
    return page, per_page, search, status_filter

# Database Configuration
DEVDB_HOST = os.environ.get('DEVDB_HOST', 'devdb')
DEVDB_PORT = os.environ.get('DEVDB_PORT', '5432')
DEVDB_USER = os.environ.get('DEVDB_USER', 'devdb_admin')
DEVDB_PASSWORD = os.environ.get('DEVDB_PASSWORD', 'devdbadmin123')
DEVDB_NAME = os.environ.get('DEVDB_NAME', 'devdb')

# Coder Configuration
CODER_URL = os.environ.get('CODER_URL', 'http://coder-server:7080')
CODER_ADMIN_EMAIL = os.environ.get('CODER_ADMIN_EMAIL', 'admin@example.com')
CODER_ADMIN_PASSWORD = os.environ.get('CODER_ADMIN_PASSWORD', 'CoderAdmin123!')

# Service URLs for monitoring
SERVICES = {
    'coder': {
        'name': 'Coder',
        'url': os.environ.get('CODER_URL', 'http://coder-server:7080'),
        'health_endpoint': '/api/v2/buildinfo',
        'dashboard_url': 'https://host.docker.internal:7443',
        'icon': 'code'
    },
    'devdb': {
        'name': 'DevDB',
        'url': f"http://{os.environ.get('DEVDB_HOST', 'devdb')}:{os.environ.get('DEVDB_PORT', '5432')}",
        'health_endpoint': None,  # Special handling for PostgreSQL
        'dashboard_url': None,
        'icon': 'database'
    },
    'gitea': {
        'name': 'Gitea',
        'url': os.environ.get('GITEA_URL', 'http://gitea:3000'),
        'health_endpoint': '/api/healthz',
        'dashboard_url': 'http://localhost:3000',
        'icon': 'git-branch'
    },
    'drone': {
        'name': 'Drone CI',
        'url': os.environ.get('DRONE_URL', 'http://drone-server:80'),
        'health_endpoint': '/healthz',
        'dashboard_url': 'http://localhost:8080',
        'icon': 'play-circle'
    },
    'minio': {
        'name': 'MinIO',
        'url': os.environ.get('MINIO_URL', 'http://minio:9002'),
        'health_endpoint': '/minio/health/live',
        'dashboard_url': 'http://localhost:9001',
        'icon': 'hard-drive'
    },
    'ai_gateway': {
        'name': 'LiteLLM',
        'url': os.environ.get('AI_GATEWAY_URL', 'http://litellm:4000'),
        'health_endpoint': '/health',
        'dashboard_url': 'http://localhost:4000/ui',
        'icon': 'cpu'
    },
    'authentik': {
        'name': 'Authentik',
        'url': os.environ.get('AUTHENTIK_URL', 'http://authentik-server:9000'),
        'health_endpoint': '/-/health/ready/',
        'dashboard_url': 'http://localhost:9000',
        'icon': 'shield'
    }
}

# Local auth fallback (for PoC - use proper auth in production)
ADMIN_USERNAME = os.environ.get('ADMIN_USERNAME', 'admin')
ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD', 'admin123')
LOCAL_AUTH_ENABLED = os.environ.get('LOCAL_AUTH_ENABLED', 'true').lower() == 'true'

# Key Provisioner (for admin reset actions)
KEY_PROVISIONER_URL = os.environ.get('KEY_PROVISIONER_URL', 'http://key-provisioner:8100')
PROVISIONER_SECRET = os.environ.get('PROVISIONER_SECRET', '')

# MinIO configuration
MINIO_ENDPOINT = os.environ.get('MINIO_ENDPOINT', 'minio:9002')
MINIO_ACCESS_KEY = os.environ.get('MINIO_ROOT_USER', 'minioadmin')
MINIO_SECRET_KEY = os.environ.get('MINIO_ROOT_PASSWORD', 'minioadmin')
MINIO_SECURE = os.environ.get('MINIO_SECURE', 'false').lower() == 'true'


def get_db_connection():
    """Get connection to DevDB"""
    return psycopg2.connect(
        host=DEVDB_HOST,
        port=DEVDB_PORT,
        user=DEVDB_USER,
        password=DEVDB_PASSWORD,
        database=DEVDB_NAME
    )


# LiteLLM Database Configuration (AI usage data)
LITELLM_DB_HOST = os.environ.get('LITELLM_DB_HOST', 'postgres')
LITELLM_DB_PORT = os.environ.get('LITELLM_DB_PORT', '5432')
LITELLM_DB_USER = os.environ.get('LITELLM_DB_USER', 'litellm')
LITELLM_DB_PASSWORD = os.environ.get('LITELLM_DB_PASSWORD', 'litellm')
LITELLM_DB_NAME = os.environ.get('LITELLM_DB_NAME', 'litellm')


def get_litellm_db_connection():
    """Get connection to LiteLLM database for AI usage data"""
    return psycopg2.connect(
        host=LITELLM_DB_HOST,
        port=LITELLM_DB_PORT,
        user=LITELLM_DB_USER,
        password=LITELLM_DB_PASSWORD,
        database=LITELLM_DB_NAME
    )


def get_minio_client():
    """Get MinIO client connection"""
    try:
        client = Minio(
            MINIO_ENDPOINT,
            access_key=MINIO_ACCESS_KEY,
            secret_key=MINIO_SECRET_KEY,
            secure=MINIO_SECURE
        )
        return client
    except Exception as e:
        app.logger.error(f"Failed to create MinIO client: {e}")
        return None


def get_minio_stats():
    """Get MinIO storage statistics"""
    client = get_minio_client()
    if not client:
        return None

    try:
        buckets = list(client.list_buckets())
        bucket_stats = []
        total_size = 0
        total_objects = 0

        for bucket in buckets:
            bucket_size = 0
            object_count = 0
            try:
                objects = client.list_objects(bucket.name, recursive=True)
                for obj in objects:
                    bucket_size += obj.size or 0
                    object_count += 1
            except Exception as e:
                app.logger.warning(f"Error listing objects in {bucket.name}: {e}")

            bucket_stats.append({
                'name': bucket.name,
                'created': bucket.creation_date.isoformat() if bucket.creation_date else None,
                'size': bucket_size,
                'size_human': format_bytes(bucket_size),
                'objects': object_count
            })
            total_size += bucket_size
            total_objects += object_count

        return {
            'status': 'healthy',
            'buckets': bucket_stats,
            'total_buckets': len(buckets),
            'total_size': total_size,
            'total_size_human': format_bytes(total_size),
            'total_objects': total_objects,
            'endpoint': MINIO_ENDPOINT
        }
    except S3Error as e:
        app.logger.error(f"MinIO S3 error: {e}")
        return {'status': 'error', 'error': str(e)}
    except Exception as e:
        app.logger.error(f"MinIO error: {e}")
        return {'status': 'error', 'error': str(e)}


def format_bytes(size):
    """Format bytes to human readable string"""
    if size == 0:
        return "0 B"
    units = ['B', 'KB', 'MB', 'GB', 'TB']
    i = 0
    while size >= 1024 and i < len(units) - 1:
        size /= 1024
        i += 1
    return f"{size:.1f} {units[i]}"


def get_coder_token():
    """Get Coder API token"""
    try:
        response = requests.post(
            f"{CODER_URL}/api/v2/users/login",
            json={
                "email": CODER_ADMIN_EMAIL,
                "password": CODER_ADMIN_PASSWORD
            },
            timeout=5
        )
        if response.ok:
            return response.json().get('session_token')
    except Exception as e:
        app.logger.error(f"Failed to get Coder token: {e}")
    return None


def get_active_workspaces():
    """Get list of active workspace IDs from Coder"""
    token = get_coder_token()
    if not token:
        return set()

    try:
        response = requests.get(
            f"{CODER_URL}/api/v2/workspaces",
            headers={"Coder-Session-Token": token},
            timeout=5
        )
        if response.ok:
            workspaces = response.json().get('workspaces', response.json())
            if isinstance(workspaces, list):
                return {ws['id'] for ws in workspaces}
            return set()
    except Exception as e:
        app.logger.error(f"Failed to get workspaces: {e}")
    return set()


def get_coder_users():
    """Get all users from Coder API"""
    token = get_coder_token()
    if not token:
        return []

    try:
        response = requests.get(
            f"{CODER_URL}/api/v2/users",
            headers={"Coder-Session-Token": token},
            timeout=10
        )
        if response.ok:
            data = response.json()
            return data.get('users', data) if isinstance(data, dict) else data
    except Exception as e:
        app.logger.error(f"Failed to get users: {e}")
    return []


def get_coder_workspaces_detailed():
    """Get all workspaces with detailed info from Coder API"""
    token = get_coder_token()
    if not token:
        return []

    try:
        response = requests.get(
            f"{CODER_URL}/api/v2/workspaces",
            headers={"Coder-Session-Token": token},
            timeout=10
        )
        if response.ok:
            data = response.json()
            return data.get('workspaces', data) if isinstance(data, dict) else data
    except Exception as e:
        app.logger.error(f"Failed to get workspaces: {e}")
    return []


def get_workspace_resources(workspace_id):
    """Get resource usage for a specific workspace"""
    token = get_coder_token()
    if not token:
        return None

    try:
        response = requests.get(
            f"{CODER_URL}/api/v2/workspaces/{workspace_id}/resources",
            headers={"Coder-Session-Token": token},
            timeout=5
        )
        if response.ok:
            return response.json()
    except Exception as e:
        app.logger.debug(f"Failed to get workspace resources: {e}")
    return None


def enrich_users_with_activity(users, workspaces, ai_usage_by_user):
    """Enrich user data with workspace and activity information"""
    # Build workspace counts and running status per user
    user_workspaces = {}
    for ws in workspaces:
        owner = ws.get('owner_name', ws.get('owner', {}).get('username', 'unknown'))
        if owner not in user_workspaces:
            user_workspaces[owner] = {'total': 0, 'running': 0, 'last_used': None}
        user_workspaces[owner]['total'] += 1

        status = ws.get('latest_build', {}).get('status', 'unknown')
        if status == 'running':
            user_workspaces[owner]['running'] += 1

        last_used = ws.get('last_used_at')
        if last_used:
            try:
                last_used_dt = datetime.fromisoformat(last_used.replace('Z', '+00:00'))
                if not user_workspaces[owner]['last_used'] or last_used_dt > user_workspaces[owner]['last_used']:
                    user_workspaces[owner]['last_used'] = last_used_dt
            except:
                pass

    enriched = []
    for user in users:
        username = user.get('username', 'unknown')
        email = user.get('email', '')

        # Get workspace info
        ws_info = user_workspaces.get(username, {'total': 0, 'running': 0, 'last_used': None})

        # Get AI usage
        ai_info = ai_usage_by_user.get(username, {'requests': 0, 'tokens': 0})

        # Determine activity status
        has_running = ws_info['running'] > 0
        last_activity = ws_info['last_used']

        # Active if has running workspace OR activity in last 7 days
        is_active = has_running
        if not is_active and last_activity:
            days_since = (datetime.now(last_activity.tzinfo) - last_activity).days
            is_active = days_since <= 7

        enriched.append({
            'username': username,
            'email': email,
            'name': user.get('name', ''),
            'created_at': user.get('created_at'),
            'last_seen_at': user.get('last_seen_at'),
            'status': user.get('status', 'active'),
            'roles': user.get('roles', []),
            'workspace_count': ws_info['total'],
            'running_workspaces': ws_info['running'],
            'last_workspace_used': ws_info['last_used'],
            'ai_requests': ai_info['requests'],
            'ai_tokens': ai_info['tokens'],
            'is_active': is_active,
            'has_running_workspace': has_running
        })

    return enriched


def enrich_workspaces_with_metrics(workspaces, ai_usage_by_workspace):
    """Enrich workspace data with resource metrics"""
    enriched = []
    for ws in workspaces:
        workspace_id = ws.get('id', '')
        owner = ws.get('owner_name', ws.get('owner', {}).get('username', 'unknown'))
        template = ws.get('template_name', 'unknown')
        latest_build = ws.get('latest_build', {})
        status = latest_build.get('status', 'unknown')

        # Get resources from latest build
        resources = latest_build.get('resources', [])
        cpu_cores = 0
        memory_gb = 0
        disk_gb = 0

        for res in resources:
            metadata = res.get('metadata', [])
            for meta in metadata:
                key = meta.get('key', '')
                value = meta.get('value', '0')
                try:
                    if 'cpu' in key.lower():
                        cpu_cores += float(value)
                    elif 'memory' in key.lower():
                        memory_gb += float(value) / 1024  # Assume MB
                    elif 'disk' in key.lower() or 'storage' in key.lower():
                        disk_gb += float(value)
                except:
                    pass

        # Get AI usage
        ai_info = ai_usage_by_workspace.get(workspace_id, {'requests': 0, 'tokens': 0})

        # Parse timestamps
        last_used = ws.get('last_used_at')
        created_at = ws.get('created_at')

        enriched.append({
            'id': workspace_id,
            'name': ws.get('name', 'unknown'),
            'owner': owner,
            'template': template,
            'status': status,
            'created_at': created_at,
            'last_used_at': last_used,
            'cpu_cores': cpu_cores or None,
            'memory_gb': memory_gb or None,
            'disk_gb': disk_gb or None,
            'ai_requests': ai_info['requests'],
            'ai_tokens': ai_info['tokens'],
            'outdated': ws.get('outdated', False)
        })

    return enriched


def require_auth(f):
    """Session-based authentication decorator"""
    @wraps(f)
    def decorated(*args, **kwargs):
        if 'user' not in session:
            return redirect(url_for('login', next=request.url))
        return f(*args, **kwargs)
    return decorated


def get_current_user():
    """Get current logged in user info"""
    return session.get('user', {})


# Admin usernames that always get full access
ADMIN_USERNAMES = {'admin', 'akadmin'}
# Authentik groups that grant admin access
ADMIN_GROUPS = {'coder-admins', 'platform-admins', 'admins'}


def is_admin():
    """Check if the current user has admin privileges."""
    user = get_current_user()
    if not user:
        return False
    # Local login is always admin (only admins know the local password)
    if user.get('auth_type') == 'local':
        return True
    # Check username
    if user.get('username', '') in ADMIN_USERNAMES:
        return True
    # Check OIDC groups
    groups = set(user.get('groups', []))
    if groups & ADMIN_GROUPS:
        return True
    return False


# =============================================================================
# Authentication Routes
# =============================================================================

@app.route('/login', methods=['GET', 'POST'])
def login():
    """Login page with OIDC and local form options"""
    error = None
    next_url = request.args.get('next', url_for('dashboard'))

    # Already logged in?
    if 'user' in session:
        return redirect(next_url)

    if request.method == 'POST':
        # Local form login
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '')

        if LOCAL_AUTH_ENABLED and username == ADMIN_USERNAME and password == ADMIN_PASSWORD:
            session['user'] = {
                'username': username,
                'email': f'{username}@local',
                'name': 'Local Admin',
                'auth_type': 'local'
            }
            flash('Logged in successfully', 'success')
            return redirect(next_url)
        else:
            error = 'Invalid username or password'

    return render_template('login.html',
        error=error,
        next_url=next_url,
        oidc_enabled=OIDC_ENABLED and bool(OIDC_CLIENT_SECRET),
        local_auth_enabled=LOCAL_AUTH_ENABLED
    )


@app.route('/login/oidc')
def login_oidc():
    """Initiate OIDC login flow"""
    if not OIDC_ENABLED or not OIDC_CLIENT_SECRET:
        flash('OIDC is not configured', 'error')
        return redirect(url_for('login'))

    next_url = request.args.get('next', url_for('dashboard'))
    session['login_next'] = next_url

    redirect_uri = url_for('auth_callback', _external=True)
    return oauth.authentik.authorize_redirect(redirect_uri)


@app.route('/auth/callback')
def auth_callback():
    """Handle OIDC callback"""
    try:
        token = oauth.authentik.authorize_access_token()
        userinfo = token.get('userinfo')

        if not userinfo:
            # Try to fetch userinfo separately
            userinfo = oauth.authentik.userinfo()

        session['user'] = {
            'username': userinfo.get('preferred_username', userinfo.get('sub', 'unknown')),
            'email': userinfo.get('email', ''),
            'name': userinfo.get('name', userinfo.get('preferred_username', '')),
            'groups': userinfo.get('groups', []),
            'auth_type': 'oidc'
        }
        flash('Logged in via SSO successfully', 'success')

    except Exception as e:
        app.logger.error(f"OIDC callback error: {e}")
        flash(f'SSO login failed: {str(e)}', 'error')
        return redirect(url_for('login'))

    next_url = session.pop('login_next', url_for('dashboard'))
    return redirect(next_url)


@app.route('/logout')
def logout():
    """Logout and clear session"""
    auth_type = session.get('user', {}).get('auth_type', 'local')
    session.clear()
    flash('Logged out successfully', 'success')

    # For OIDC, optionally redirect to Authentik logout
    # For now, just redirect to login page
    return redirect(url_for('login'))


# =============================================================================
# Context Processors
# =============================================================================

@app.context_processor
def inject_user():
    """Inject current user into all templates"""
    return {'current_user': get_current_user()}


@app.route('/')
@require_auth
def dashboard():
    """Main dashboard view"""
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    # Get all databases
    cur.execute("""
        SELECT
            d.db_name,
            d.db_type,
            d.owner_username,
            d.template_name,
            d.workspace_id,
            d.created_at,
            d.last_accessed,
            (SELECT COUNT(*) FROM provisioning.db_users u WHERE u.db_name = d.db_name) as user_count
        FROM provisioning.databases d
        ORDER BY d.db_type, d.last_accessed DESC
    """)
    databases = cur.fetchall()

    # Get summary
    cur.execute("SELECT * FROM provisioning.database_summary")
    summary_rows = cur.fetchall()
    summary = {row['db_type']: row for row in summary_rows}

    # Get database sizes
    cur.execute("""
        SELECT datname, pg_database_size(datname) as size_bytes
        FROM pg_database
        WHERE datname LIKE 'dev_%' OR datname LIKE 'team_%'
    """)
    sizes = {row['datname']: row['size_bytes'] for row in cur.fetchall()}

    # Get active connections
    cur.execute("""
        SELECT datname, COUNT(*) as conn_count
        FROM pg_stat_activity
        WHERE datname LIKE 'dev_%' OR datname LIKE 'team_%'
        GROUP BY datname
    """)
    connections = {row['datname']: row['conn_count'] for row in cur.fetchall()}

    conn.close()

    # Check for orphans
    active_workspaces = get_active_workspaces()

    # Enrich database info
    for db in databases:
        db['size_bytes'] = sizes.get(db['db_name'], 0)
        db['size_human'] = format_size(db['size_bytes'])
        db['connections'] = connections.get(db['db_name'], 0)
        db['days_inactive'] = (datetime.now(db['last_accessed'].tzinfo) - db['last_accessed']).days if db['last_accessed'] else 999

        # Check if orphaned
        db['is_orphan'] = False
        if db['db_type'] == 'individual':
            if db['workspace_id'] and db['workspace_id'] not in active_workspaces:
                db['is_orphan'] = True
                db['orphan_reason'] = 'Workspace deleted'
            elif not db['workspace_id'] and db['days_inactive'] > 30:
                db['is_orphan'] = True
                db['orphan_reason'] = 'No workspace, inactive'

    # Calculate totals
    total_individual = sum(1 for db in databases if db['db_type'] == 'individual')
    total_team = sum(1 for db in databases if db['db_type'] == 'team')
    total_orphans = sum(1 for db in databases if db.get('is_orphan'))
    total_size = sum(db['size_bytes'] for db in databases)

    return render_template('dashboard.html',
        databases=databases,
        summary=summary,
        total_individual=total_individual,
        total_team=total_team,
        total_orphans=total_orphans,
        total_size=format_size(total_size),
        coder_connected=bool(active_workspaces or get_coder_token())
    )


@app.route('/api/databases')
@require_auth
def api_databases():
    """API endpoint for database list"""
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    cur.execute("""
        SELECT * FROM provisioning.databases
        ORDER BY db_type, last_accessed DESC
    """)
    databases = cur.fetchall()
    conn.close()

    # Convert datetime to string
    for db in databases:
        db['created_at'] = db['created_at'].isoformat() if db['created_at'] else None
        db['last_accessed'] = db['last_accessed'].isoformat() if db['last_accessed'] else None

    return jsonify(databases)


@app.route('/api/database/<db_name>')
@require_auth
def api_database_detail(db_name):
    """API endpoint for database details"""
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    cur.execute("SELECT * FROM provisioning.databases WHERE db_name = %s", (db_name,))
    database = cur.fetchone()

    if not database:
        return jsonify({'error': 'Database not found'}), 404

    cur.execute("SELECT * FROM provisioning.db_users WHERE db_name = %s", (db_name,))
    users = cur.fetchall()

    cur.execute("SELECT pg_database_size(%s) as size", (db_name,))
    size = cur.fetchone()

    conn.close()

    return jsonify({
        'database': database,
        'users': users,
        'size_bytes': size['size'] if size else 0,
        'size_human': format_size(size['size']) if size else '0 B'
    })


@app.route('/create-team', methods=['POST'])
@require_auth
def create_team_database():
    """Create a new team database"""
    team_name = request.form.get('team_name', '').strip()

    if not team_name:
        flash('Team name is required', 'error')
        return redirect(url_for('dashboard'))

    if not team_name.replace('-', '').replace('_', '').isalnum():
        flash('Team name must be alphanumeric (dashes and underscores allowed)', 'error')
        return redirect(url_for('dashboard'))

    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    try:
        cur.execute("SELECT * FROM provisioning.create_team_db(%s)", (team_name,))
        result = cur.fetchone()
        conn.commit()
        flash(f"Team database created: {result['db_name']}", 'success')
    except Exception as e:
        conn.rollback()
        flash(f"Failed to create database: {e}", 'error')
    finally:
        conn.close()

    return redirect(url_for('dashboard'))


@app.route('/delete/<db_name>', methods=['POST'])
@require_auth
def delete_database(db_name):
    """Delete a database"""
    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Terminate connections
        cur.execute("""
            SELECT pg_terminate_backend(pid)
            FROM pg_stat_activity
            WHERE datname = %s
        """, (db_name,))

        # Delete from provisioning tables first
        cur.execute("DELETE FROM provisioning.db_users WHERE db_name = %s", (db_name,))
        cur.execute("DELETE FROM provisioning.databases WHERE db_name = %s", (db_name,))
        conn.commit()
        conn.close()

        # Drop database (need new connection to postgres db)
        conn = psycopg2.connect(
            host=DEVDB_HOST,
            port=DEVDB_PORT,
            user=DEVDB_USER,
            password=DEVDB_PASSWORD,
            database='postgres'
        )
        conn.autocommit = True
        cur = conn.cursor()
        cur.execute(f'DROP DATABASE IF EXISTS "{db_name}"')
        cur.execute(f'DROP USER IF EXISTS "{db_name}"')
        conn.close()

        flash(f"Database deleted: {db_name}", 'success')
    except Exception as e:
        flash(f"Failed to delete database: {e}", 'error')

    return redirect(url_for('dashboard'))


@app.route('/cleanup-orphans', methods=['POST'])
@require_auth
def cleanup_orphans():
    """Delete all orphaned databases"""
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    # Get orphaned databases (>90 days inactive)
    cur.execute("""
        SELECT db_name FROM provisioning.databases
        WHERE db_type = 'individual'
          AND last_accessed < NOW() - INTERVAL '90 days'
    """)
    orphans = [row['db_name'] for row in cur.fetchall()]
    conn.close()

    deleted = 0
    for db_name in orphans:
        try:
            # Reuse delete logic
            conn = get_db_connection()
            cur = conn.cursor()
            cur.execute("DELETE FROM provisioning.db_users WHERE db_name = %s", (db_name,))
            cur.execute("DELETE FROM provisioning.databases WHERE db_name = %s", (db_name,))
            conn.commit()
            conn.close()

            conn = psycopg2.connect(
                host=DEVDB_HOST, port=DEVDB_PORT,
                user=DEVDB_USER, password=DEVDB_PASSWORD,
                database='postgres'
            )
            conn.autocommit = True
            cur = conn.cursor()
            cur.execute(f'DROP DATABASE IF EXISTS "{db_name}"')
            cur.execute(f'DROP USER IF EXISTS "{db_name}"')
            conn.close()
            deleted += 1
        except Exception as e:
            app.logger.error(f"Failed to delete {db_name}: {e}")

    flash(f"Cleaned up {deleted} orphaned databases", 'success')
    return redirect(url_for('dashboard'))


@app.route('/health')
def health():
    """Health check endpoint"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        conn.close()
        return jsonify({'status': 'healthy', 'database': 'connected'})
    except Exception as e:
        return jsonify({'status': 'unhealthy', 'error': str(e)}), 500


def format_size(size_bytes):
    """Format bytes to human readable size"""
    if size_bytes is None:
        return '0 B'
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if abs(size_bytes) < 1024.0:
            return f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.1f} PB"


def check_service_health(service_key, service_config):
    """Check health of a single service"""
    result = {
        'key': service_key,
        'name': service_config['name'],
        'status': 'unknown',
        'response_time': None,
        'error': None,
        'icon': service_config.get('icon', 'server'),
        'dashboard_url': service_config.get('dashboard_url')
    }

    start_time = datetime.now()

    # Special handling for PostgreSQL (DevDB)
    if service_config.get('health_endpoint') is None and 'devdb' in service_key:
        try:
            conn = get_db_connection()
            cur = conn.cursor()
            cur.execute("SELECT 1")
            conn.close()
            result['status'] = 'healthy'
            result['response_time'] = (datetime.now() - start_time).total_seconds() * 1000
        except Exception as e:
            result['status'] = 'unhealthy'
            result['error'] = str(e)
        return result

    # HTTP health check
    try:
        url = service_config['url'] + service_config.get('health_endpoint', '/')
        response = requests.get(url, timeout=5)
        result['response_time'] = (datetime.now() - start_time).total_seconds() * 1000

        if response.ok:
            result['status'] = 'healthy'
        else:
            result['status'] = 'degraded'
            result['error'] = f"HTTP {response.status_code}"
    except requests.exceptions.ConnectionError:
        result['status'] = 'unhealthy'
        result['error'] = 'Connection refused'
    except requests.exceptions.Timeout:
        result['status'] = 'unhealthy'
        result['error'] = 'Timeout'
    except Exception as e:
        result['status'] = 'unhealthy'
        result['error'] = str(e)

    return result


def check_all_services():
    """Check health of all services in parallel"""
    results = []

    with ThreadPoolExecutor(max_workers=len(SERVICES)) as executor:
        futures = {
            executor.submit(check_service_health, key, config): key
            for key, config in SERVICES.items()
        }

        for future in as_completed(futures):
            try:
                result = future.result()
                results.append(result)
            except Exception as e:
                app.logger.error(f"Health check failed: {e}")

    # Sort by name for consistent display
    return sorted(results, key=lambda x: x['name'])


@app.route('/services')
@require_auth
def services():
    """Service health monitoring page"""
    service_status = check_all_services()

    healthy_count = sum(1 for s in service_status if s['status'] == 'healthy')
    total_count = len(service_status)

    return render_template('services.html',
        services=service_status,
        healthy_count=healthy_count,
        total_count=total_count
    )


@app.route('/api/services')
@require_auth
def api_services():
    """API endpoint for service health"""
    return jsonify(check_all_services())


# =============================================================================
# AI Usage Tracking
# =============================================================================

@app.route('/ai-usage')
@require_auth
def ai_usage():
    """AI usage tracking dashboard - reads from LiteLLM's database"""
    try:
        conn = get_litellm_db_connection()
    except Exception as e:
        app.logger.error(f"Failed to connect to LiteLLM database: {e}")
        # Render with empty data and error
        empty_totals = {
            'total_tokens_in': 0, 'total_tokens_out': 0,
            'total_requests': 0, 'unique_users': 0, 'total_spend': 0.0
        }
        return render_template('ai_usage.html',
            week_totals=empty_totals, daily_data=[], by_provider=[],
            by_user=[], by_model=[], by_api_key=[], recent_requests=[],
            db_error=str(e)
        )

    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    # Get current week's totals from LiteLLM_SpendLogs
    cur.execute("""
        SELECT
            COALESCE(SUM(prompt_tokens), 0) as total_tokens_in,
            COALESCE(SUM(completion_tokens), 0) as total_tokens_out,
            COUNT(*) as total_requests,
            COUNT(DISTINCT "user") as unique_users,
            COALESCE(SUM(spend), 0) as total_spend
        FROM "LiteLLM_SpendLogs"
        WHERE "startTime" >= DATE_TRUNC('week', CURRENT_TIMESTAMP)
    """)
    week_totals = cur.fetchone()

    # Get daily breakdown for the last 7 days
    cur.execute("""
        SELECT
            DATE("startTime") as date,
            COUNT(*) as requests,
            COALESCE(SUM(prompt_tokens), 0) as tokens_in,
            COALESCE(SUM(completion_tokens), 0) as tokens_out,
            COALESCE(SUM(spend), 0) as spend
        FROM "LiteLLM_SpendLogs"
        WHERE "startTime" >= CURRENT_DATE - INTERVAL '7 days'
        GROUP BY DATE("startTime")
        ORDER BY date
    """)
    daily_data = cur.fetchall()

    # Get usage by provider
    cur.execute("""
        SELECT
            COALESCE(custom_llm_provider, 'unknown') as provider,
            COUNT(*) as requests,
            COALESCE(SUM(prompt_tokens), 0) as tokens_in,
            COALESCE(SUM(completion_tokens), 0) as tokens_out,
            COALESCE(SUM(spend), 0) as spend,
            COUNT(DISTINCT "user") as unique_users
        FROM "LiteLLM_SpendLogs"
        WHERE "startTime" >= DATE_TRUNC('week', CURRENT_TIMESTAMP)
        GROUP BY custom_llm_provider
        ORDER BY tokens_out DESC
    """)
    by_provider = cur.fetchall()

    # Get usage by user
    cur.execute("""
        SELECT
            COALESCE("user", 'anonymous') as user_id,
            COUNT(*) as requests,
            COALESCE(SUM(prompt_tokens), 0) as tokens_in,
            COALESCE(SUM(completion_tokens), 0) as tokens_out,
            COALESCE(SUM(spend), 0) as spend
        FROM "LiteLLM_SpendLogs"
        WHERE "startTime" >= DATE_TRUNC('week', CURRENT_TIMESTAMP)
        GROUP BY "user"
        ORDER BY tokens_out DESC
        LIMIT 20
    """)
    by_user = cur.fetchall()

    # Get usage by model (replaces "by template")
    cur.execute("""
        SELECT
            COALESCE(model_group, model, 'unknown') as model_name,
            COUNT(*) as requests,
            COALESCE(SUM(prompt_tokens), 0) as tokens_in,
            COALESCE(SUM(completion_tokens), 0) as tokens_out,
            COALESCE(SUM(spend), 0) as spend,
            COUNT(DISTINCT "user") as unique_users
        FROM "LiteLLM_SpendLogs"
        WHERE "startTime" >= DATE_TRUNC('week', CURRENT_TIMESTAMP)
        GROUP BY model_group, model
        ORDER BY tokens_out DESC
    """)
    by_model = cur.fetchall()

    # Get usage by API key (replaces "by workspace")
    cur.execute("""
        SELECT
            COALESCE(api_key, 'unknown') as api_key,
            COALESCE("user", 'unknown') as user_id,
            COUNT(*) as requests,
            COALESCE(SUM(prompt_tokens), 0) as tokens_in,
            COALESCE(SUM(completion_tokens), 0) as tokens_out,
            COALESCE(SUM(spend), 0) as spend
        FROM "LiteLLM_SpendLogs"
        WHERE "startTime" >= DATE_TRUNC('week', CURRENT_TIMESTAMP)
        GROUP BY api_key, "user"
        ORDER BY tokens_out DESC
        LIMIT 20
    """)
    by_api_key = cur.fetchall()

    # Get recent requests
    cur.execute("""
        SELECT
            "startTime" as timestamp,
            "endTime" as end_time,
            COALESCE("user", 'anonymous') as user_id,
            COALESCE(custom_llm_provider, 'unknown') as provider,
            COALESCE(model, 'unknown') as model,
            COALESCE(prompt_tokens, 0) as tokens_in,
            COALESCE(completion_tokens, 0) as tokens_out,
            COALESCE(spend, 0) as spend,
            CASE
                WHEN "endTime" IS NOT NULL AND "startTime" IS NOT NULL
                THEN EXTRACT(EPOCH FROM ("endTime" - "startTime")) * 1000
                ELSE NULL
            END as latency_ms
        FROM "LiteLLM_SpendLogs"
        ORDER BY "startTime" DESC
        LIMIT 50
    """)
    recent_requests = cur.fetchall()

    # Get per-user budget/spend status from LiteLLM_UserTable
    user_budgets = {}
    try:
        cur.execute("""
            SELECT
                user_id,
                COALESCE(spend, 0) as spend,
                max_budget,
                rpm_limit,
                tpm_limit,
                max_parallel_requests,
                budget_duration
            FROM "LiteLLM_UserTable"
        """)
        for row in cur.fetchall():
            user_budgets[row['user_id']] = row
    except Exception as e:
        app.logger.warning(f"Could not fetch user budgets (table may not exist): {e}")

    conn.close()

    return render_template('ai_usage.html',
        week_totals=week_totals,
        daily_data=daily_data,
        by_provider=by_provider,
        by_user=by_user,
        by_model=by_model,
        by_api_key=by_api_key,
        recent_requests=recent_requests,
        user_budgets=user_budgets,
    )


@app.route('/api/ai-usage')
@require_auth
def api_ai_usage():
    """API endpoint for AI usage data - reads from LiteLLM's database"""
    try:
        conn = get_litellm_db_connection()
    except Exception as e:
        return jsonify({'error': f'Failed to connect to LiteLLM database: {e}'}), 503

    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    period = request.args.get('period', 'week')
    intervals = {
        'day': "INTERVAL '1 day'",
        'month': "INTERVAL '30 days'",
        'year': "INTERVAL '365 days'",
    }
    interval = intervals.get(period, "INTERVAL '7 days'")

    cur.execute(f"""
        SELECT
            DATE("startTime") as date,
            COALESCE(custom_llm_provider, 'unknown') as provider,
            COALESCE("user", 'anonymous') as user_id,
            COALESCE(model_group, model, 'unknown') as model,
            COUNT(*) as requests,
            COALESCE(SUM(prompt_tokens), 0) as tokens_in,
            COALESCE(SUM(completion_tokens), 0) as tokens_out,
            COALESCE(SUM(spend), 0) as spend
        FROM "LiteLLM_SpendLogs"
        WHERE "startTime" >= CURRENT_TIMESTAMP - {interval}
        GROUP BY DATE("startTime"), custom_llm_provider, "user", model_group, model
        ORDER BY date DESC
    """)
    data = cur.fetchall()
    conn.close()

    for row in data:
        row['date'] = row['date'].isoformat() if row['date'] else None
        row['spend'] = float(row['spend']) if row['spend'] else 0.0

    return jsonify(data)


@app.route('/api/ai-usage/reset-user', methods=['POST'])
@require_auth
def api_reset_user_spend():
    """Reset a user's AI spend (admin action via key-provisioner)."""
    body = request.get_json(silent=True) or {}
    user_id = body.get('user_id', '').strip()
    if not user_id:
        return jsonify({'error': 'user_id required'}), 400

    try:
        resp = requests.post(
            f"{KEY_PROVISIONER_URL}/api/v1/keys/reset-user",
            headers={
                "Authorization": f"Bearer {PROVISIONER_SECRET}",
                "Content-Type": "application/json",
            },
            json={"user_id": user_id},
            timeout=10,
        )
        if resp.ok:
            return jsonify(resp.json())
        return jsonify({'error': f'Reset failed: {resp.text}'}), resp.status_code
    except Exception as e:
        app.logger.error(f"Failed to reset user spend: {e}")
        return jsonify({'error': 'Key provisioner unavailable'}), 502


# =============================================================================
# Users Management
# =============================================================================

@app.route('/users')
@require_auth
def users():
    """Users management page with activity tracking"""
    page, per_page, search, status_filter = get_pagination_args()

    # Get users from Coder
    coder_users = get_coder_users()
    workspaces = get_coder_workspaces_detailed()

    # Get AI usage by user from LiteLLM database
    ai_usage_by_user = {}
    try:
        conn = get_litellm_db_connection()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute("""
            SELECT
                COALESCE("user", 'anonymous') as user_id,
                COUNT(*) as requests,
                COALESCE(SUM(prompt_tokens + completion_tokens), 0) as tokens
            FROM "LiteLLM_SpendLogs"
            WHERE "startTime" >= DATE_TRUNC('week', CURRENT_TIMESTAMP)
            GROUP BY "user"
        """)
        ai_usage_rows = cur.fetchall()
        conn.close()
        ai_usage_by_user = {row['user_id']: row for row in ai_usage_rows}
    except Exception as e:
        app.logger.warning(f"Could not fetch AI usage from LiteLLM DB: {e}")

    # Enrich users
    enriched_users = enrich_users_with_activity(coder_users, workspaces, ai_usage_by_user)

    # Apply search filter
    if search:
        search_lower = search.lower()
        enriched_users = [u for u in enriched_users
            if search_lower in u['username'].lower()
            or search_lower in u.get('email', '').lower()
            or search_lower in u.get('name', '').lower()]

    # Apply status filter
    if status_filter == 'active':
        enriched_users = [u for u in enriched_users if u['is_active']]
    elif status_filter == 'inactive':
        enriched_users = [u for u in enriched_users if not u['is_active']]
    elif status_filter == 'running':
        enriched_users = [u for u in enriched_users if u['has_running_workspace']]

    # Sort by activity (running workspaces first, then by last activity)
    enriched_users.sort(key=lambda u: (
        -u['running_workspaces'],
        -(u['ai_requests'] or 0),
        u['last_workspace_used'] or datetime.min.replace(tzinfo=None)
    ), reverse=True)

    # Pagination
    total = len(enriched_users)
    start = (page - 1) * per_page
    end = start + per_page
    paginated_users = enriched_users[start:end]

    pagination = Pagination(page, per_page, total, paginated_users)

    # Summary stats
    total_users = len(coder_users)
    active_users = sum(1 for u in enriched_users if u['is_active'])
    users_with_workspaces = sum(1 for u in enriched_users if u['workspace_count'] > 0)

    return render_template('users.html',
        users=paginated_users,
        pagination=pagination,
        total_users=total_users,
        active_users=active_users,
        users_with_workspaces=users_with_workspaces,
        search=search,
        status_filter=status_filter
    )


@app.route('/api/users')
@require_auth
def api_users():
    """API endpoint for users list"""
    coder_users = get_coder_users()
    workspaces = get_coder_workspaces_detailed()

    ai_usage = {}
    try:
        conn = get_litellm_db_connection()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute("""
            SELECT "user" as user_id, COUNT(*) as requests, SUM(prompt_tokens + completion_tokens) as tokens
            FROM "LiteLLM_SpendLogs"
            WHERE "startTime" >= DATE_TRUNC('week', CURRENT_TIMESTAMP)
            GROUP BY "user"
        """)
        ai_usage = {row['user_id']: row for row in cur.fetchall()}
        conn.close()
    except Exception as e:
        app.logger.warning(f"Could not fetch AI usage from LiteLLM DB: {e}")

    enriched = enrich_users_with_activity(coder_users, workspaces, ai_usage)

    # Convert datetime objects
    for user in enriched:
        if user.get('last_workspace_used'):
            user['last_workspace_used'] = user['last_workspace_used'].isoformat()

    return jsonify(enriched)


# =============================================================================
# Workspaces Management
# =============================================================================

@app.route('/workspaces')
@require_auth
def workspaces():
    """Workspaces management page with resource metrics"""
    page, per_page, search, status_filter = get_pagination_args()
    template_filter = request.args.get('template', '')
    owner_filter = request.args.get('owner', '')

    # Get workspaces from Coder
    coder_workspaces = get_coder_workspaces_detailed()

    # AI usage by workspace not directly available from LiteLLM (no workspace_id field)
    ai_usage_by_workspace = {}

    # Enrich workspaces
    enriched_workspaces = enrich_workspaces_with_metrics(coder_workspaces, ai_usage_by_workspace)

    # Get unique templates and owners for filter dropdowns
    all_templates = sorted(set(ws['template'] for ws in enriched_workspaces))
    all_owners = sorted(set(ws['owner'] for ws in enriched_workspaces))

    # Apply search filter
    if search:
        search_lower = search.lower()
        enriched_workspaces = [ws for ws in enriched_workspaces
            if search_lower in ws['name'].lower()
            or search_lower in ws['owner'].lower()
            or search_lower in ws['template'].lower()]

    # Apply status filter
    if status_filter:
        enriched_workspaces = [ws for ws in enriched_workspaces if ws['status'] == status_filter]

    # Apply template filter
    if template_filter:
        enriched_workspaces = [ws for ws in enriched_workspaces if ws['template'] == template_filter]

    # Apply owner filter
    if owner_filter:
        enriched_workspaces = [ws for ws in enriched_workspaces if ws['owner'] == owner_filter]

    # Sort by status (running first) then by last used
    status_order = {'running': 0, 'starting': 1, 'stopping': 2, 'stopped': 3, 'failed': 4}
    enriched_workspaces.sort(key=lambda ws: (
        status_order.get(ws['status'], 5),
        ws['last_used_at'] or ''
    ), reverse=False)

    # Pagination
    total = len(enriched_workspaces)
    start = (page - 1) * per_page
    end = start + per_page
    paginated_workspaces = enriched_workspaces[start:end]

    pagination = Pagination(page, per_page, total, paginated_workspaces)

    # Summary stats
    total_workspaces = len(coder_workspaces)
    running_workspaces = sum(1 for ws in enriched_workspaces if ws['status'] == 'running')
    stopped_workspaces = sum(1 for ws in enriched_workspaces if ws['status'] == 'stopped')

    return render_template('workspaces.html',
        workspaces=paginated_workspaces,
        pagination=pagination,
        total_workspaces=total_workspaces,
        running_workspaces=running_workspaces,
        stopped_workspaces=stopped_workspaces,
        all_templates=all_templates,
        all_owners=all_owners,
        search=search,
        status_filter=status_filter,
        template_filter=template_filter,
        owner_filter=owner_filter
    )


@app.route('/api/workspaces')
@require_auth
def api_workspaces():
    """API endpoint for workspaces list"""
    coder_workspaces = get_coder_workspaces_detailed()

    # AI usage by workspace not directly available from LiteLLM
    ai_usage = {}

    enriched = enrich_workspaces_with_metrics(coder_workspaces, ai_usage)
    return jsonify(enriched)


# =============================================================================
# MinIO Storage Management
# =============================================================================

@app.route('/storage')
@require_auth
def storage():
    """MinIO storage management page"""
    minio_stats = get_minio_stats()
    return render_template('storage.html',
        minio=minio_stats,
        minio_console_url='http://localhost:9001'
    )


@app.route('/api/storage')
@require_auth
def api_storage():
    """API endpoint for MinIO storage stats"""
    return jsonify(get_minio_stats())


@app.route('/api/storage/bucket/<bucket_name>')
@require_auth
def api_bucket_details(bucket_name):
    """API endpoint for bucket details"""
    client = get_minio_client()
    if not client:
        return jsonify({'error': 'MinIO not available'}), 503

    try:
        objects = []
        total_size = 0
        for obj in client.list_objects(bucket_name, recursive=True):
            objects.append({
                'name': obj.object_name,
                'size': obj.size,
                'size_human': format_bytes(obj.size) if obj.size else '0 B',
                'last_modified': obj.last_modified.isoformat() if obj.last_modified else None
            })
            total_size += obj.size or 0

        return jsonify({
            'bucket': bucket_name,
            'objects': objects,
            'total_objects': len(objects),
            'total_size': total_size,
            'total_size_human': format_bytes(total_size)
        })
    except S3Error as e:
        return jsonify({'error': str(e)}), 404


# =============================================================================
# AI Keys Management
# =============================================================================

LITELLM_URL = os.environ.get('LITELLM_URL', 'http://litellm:4000')
LITELLM_MASTER_KEY = os.environ.get('LITELLM_MASTER_KEY', '')

@app.route('/ai-keys')
@require_auth
def ai_keys():
    """AI API key management page — lists all LiteLLM virtual keys with spend/budget.

    Non-admin users only see their own keys (matched by username in metadata).
    """
    keys = []
    error = None
    admin = is_admin()
    username = get_current_user().get('username', '')

    try:
        conn = get_litellm_db_connection()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute("""
            SELECT
                token,
                key_name,
                key_alias,
                spend,
                max_budget,
                metadata,
                expires,
                models,
                tpm_limit,
                rpm_limit,
                max_parallel_requests,
                budget_duration,
                created_at,
                updated_at
            FROM "LiteLLM_VerificationToken"
            ORDER BY key_alias NULLS LAST, created_at DESC
        """)
        keys = cur.fetchall()
        conn.close()

        # Parse metadata JSON
        for k in keys:
            if isinstance(k.get('metadata'), str):
                try:
                    k['metadata'] = json.loads(k['metadata'])
                except Exception:
                    k['metadata'] = {}
            elif k.get('metadata') is None:
                k['metadata'] = {}

        # Non-admin: filter to only keys belonging to this user
        if not admin and username:
            keys = [k for k in keys if _key_belongs_to_user(k, username)]

    except Exception as e:
        app.logger.error(f"Failed to fetch AI keys: {e}")
        error = str(e)

    return render_template('ai_keys.html',
                           keys=keys,
                           error=error,
                           is_admin=admin,
                           current_user=session.get('user'))


def _key_belongs_to_user(key, username):
    """Check if a LiteLLM key belongs to a given user."""
    meta = key.get('metadata', {})
    # workspace keys: workspace_owner field
    if meta.get('workspace_owner') == username:
        return True
    # user keys: username field
    if meta.get('username') == username:
        return True
    # bootstrap keys from setup script: workspace_user field
    if meta.get('workspace_user') == username:
        return True
    # key_alias pattern: user-{username} or {username}
    alias = key.get('key_alias', '') or ''
    if alias == username or alias == f'user-{username}':
        return True
    # scope pattern: user:{username}
    scope = meta.get('scope', '')
    if scope == f'user:{username}':
        return True
    return False


@app.route('/api/ai-keys/revoke', methods=['POST'])
@require_auth
def revoke_ai_key():
    """Revoke (delete) an AI key by its token hash.

    Non-admin users can only revoke keys that belong to them.
    """
    data = request.get_json()
    token_hash = data.get('token')
    if not token_hash or not LITELLM_MASTER_KEY:
        return jsonify({'error': 'Missing token or master key not configured'}), 400

    # Non-admins: verify ownership before allowing revoke
    if not is_admin():
        username = get_current_user().get('username', '')
        try:
            conn = get_litellm_db_connection()
            cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
            cur.execute(
                'SELECT token, key_alias, metadata FROM "LiteLLM_VerificationToken" WHERE token = %s',
                (token_hash,))
            row = cur.fetchone()
            conn.close()
            if not row:
                return jsonify({'error': 'Key not found'}), 404
            if isinstance(row.get('metadata'), str):
                try:
                    row['metadata'] = json.loads(row['metadata'])
                except Exception:
                    row['metadata'] = {}
            elif row.get('metadata') is None:
                row['metadata'] = {}
            if not _key_belongs_to_user(row, username):
                return jsonify({'error': 'You can only revoke your own keys'}), 403
        except Exception as e:
            app.logger.error(f"Ownership check failed: {e}")
            return jsonify({'error': 'Could not verify key ownership'}), 500

    try:
        resp = requests.post(
            f"{LITELLM_URL}/key/delete",
            headers={"Authorization": f"Bearer {LITELLM_MASTER_KEY}",
                     "Content-Type": "application/json"},
            json={"keys": [token_hash]},
            timeout=10,
        )
        if resp.ok:
            return jsonify({'success': True})
        return jsonify({'error': resp.text}), resp.status_code
    except Exception as e:
        return jsonify({'error': str(e)}), 502


@app.route('/api/ai-keys/generate', methods=['POST'])
@require_auth
def generate_ai_key():
    """Generate a new AI key via key-provisioner.

    The key's owner is always the logged-in user so it appears in their key list.
    The alias is used as a human-readable label.
    """
    data = request.get_json()
    alias = data.get('alias', '')
    scope = data.get('scope', 'user')
    current = get_current_user()
    username = current.get('username', alias)

    if not PROVISIONER_SECRET:
        return jsonify({'error': 'PROVISIONER_SECRET not configured'}), 500

    try:
        resp = requests.post(
            f"{KEY_PROVISIONER_URL}/api/v1/keys/workspace",
            headers={"Authorization": f"Bearer {PROVISIONER_SECRET}",
                     "Content-Type": "application/json"},
            json={
                "workspace_id": alias or f"{username}-key",
                "workspace_name": alias,
                "username": username,
                "scope": scope,
            },
            timeout=10,
        )
        if resp.ok:
            result = resp.json()
            return jsonify({
                'success': True,
                'key': result.get('key', ''),
                'alias': result.get('alias', alias),
            })
        return jsonify({'error': resp.text}), resp.status_code
    except Exception as e:
        return jsonify({'error': str(e)}), 502


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
