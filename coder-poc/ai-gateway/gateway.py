#!/usr/bin/env python3
"""
AI Gateway - Multi-provider AI API Proxy
Supports: Anthropic Claude, AWS Bedrock, Google Gemini (planned)
Features: Usage tracking persisted to DevDB, JWT authentication
"""

import os
import json
import time
import logging
import uuid
import hmac
import hashlib
from datetime import datetime
from typing import Optional, Dict, Any
from contextlib import contextmanager
from functools import wraps

import httpx
import boto3
import yaml
import uvicorn
import psycopg2
import psycopg2.pool
from fastapi import FastAPI, Request, HTTPException, Header, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, validator
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='{"timestamp":"%(asctime)s","level":"%(levelname)s","message":"%(message)s"}'
)
logger = logging.getLogger(__name__)

# Load configuration
def load_config():
    config_path = os.getenv("CONFIG_PATH", "/app/config.yaml")
    if os.path.exists(config_path):
        with open(config_path) as f:
            return yaml.safe_load(f)
    return {}

config = load_config()

# =============================================================================
# Authentication Configuration
# =============================================================================

# Authentication settings
AUTH_ENABLED = os.getenv("AI_GATEWAY_AUTH_ENABLED", "true").lower() == "true"
AUTH_SECRET_KEY = os.getenv("AI_GATEWAY_AUTH_SECRET", "")
CODER_URL = os.getenv("CODER_URL", "http://coder-server:7080")
ALLOWED_ORIGINS = os.getenv("AI_GATEWAY_ALLOWED_ORIGINS", "").split(",") if os.getenv("AI_GATEWAY_ALLOWED_ORIGINS") else []

# Security bearer token scheme
security = HTTPBearer(auto_error=False)

async def verify_workspace_token(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    x_workspace_id: Optional[str] = Header(None),
    x_api_key: Optional[str] = Header(None)
) -> Dict[str, Any]:
    """
    Verify the request is authenticated.
    Supports:
    1. Bearer token (Coder session token validation)
    2. X-API-Key header (service-to-service with shared secret)
    3. Workspace ID header (for internal network only)
    """
    # If auth is disabled (dev mode), allow all requests
    if not AUTH_ENABLED:
        return {"workspace_id": x_workspace_id or "anonymous", "authenticated": False}

    # Method 1: API Key authentication (for service-to-service)
    if x_api_key and AUTH_SECRET_KEY:
        if hmac.compare_digest(x_api_key, AUTH_SECRET_KEY):
            return {"workspace_id": x_workspace_id or "service", "authenticated": True, "method": "api_key"}
        raise HTTPException(status_code=401, detail="Invalid API key")

    # Method 2: Bearer token (Coder session token)
    if credentials and credentials.credentials:
        token = credentials.credentials
        try:
            # Validate token against Coder API
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(
                    f"{CODER_URL}/api/v2/users/me",
                    headers={"Coder-Session-Token": token}
                )
                if response.status_code == 200:
                    user_data = response.json()
                    return {
                        "workspace_id": x_workspace_id or "authenticated",
                        "user_id": user_data.get("id"),
                        "username": user_data.get("username"),
                        "authenticated": True,
                        "method": "coder_token"
                    }
        except Exception as e:
            logger.warning(f"Token validation failed: {e}")

        raise HTTPException(status_code=401, detail="Invalid or expired token")

    # Method 3: If no auth provided but workspace_id header present (internal network)
    # This is less secure but allows internal services to communicate
    if x_workspace_id and not AUTH_SECRET_KEY:
        logger.warning(f"Unauthenticated request with workspace_id: {x_workspace_id}")
        return {"workspace_id": x_workspace_id, "authenticated": False, "method": "header_only"}

    # No valid authentication
    raise HTTPException(
        status_code=401,
        detail="Authentication required. Provide Bearer token or X-API-Key header."
    )

# =============================================================================
# Database Connection Pool for Usage Tracking
# =============================================================================
DB_HOST = os.getenv("DEVDB_HOST", "devdb")
DB_PORT = os.getenv("DEVDB_PORT", "5432")
DB_USER = os.getenv("DEVDB_USER", "ai_gateway")
DB_PASSWORD = os.getenv("DEVDB_PASSWORD", "aigateway123")
DB_NAME = os.getenv("DEVDB_NAME", "devdb")

# Connection pool (lazy initialized)
db_pool = None

def get_db_pool():
    """Get or create database connection pool"""
    global db_pool
    if db_pool is None:
        try:
            db_pool = psycopg2.pool.ThreadedConnectionPool(
                minconn=1,
                maxconn=5,
                host=DB_HOST,
                port=DB_PORT,
                user=DB_USER,
                password=DB_PASSWORD,
                database=DB_NAME
            )
            logger.info(f"Database pool created: {DB_HOST}:{DB_PORT}/{DB_NAME}")
        except Exception as e:
            logger.warning(f"Failed to create database pool: {e}")
            return None
    return db_pool

@contextmanager
def get_db_connection():
    """Context manager for database connections"""
    pool = get_db_pool()
    if pool is None:
        yield None
        return

    conn = None
    try:
        conn = pool.getconn()
        yield conn
    finally:
        if conn:
            pool.putconn(conn)

def persist_usage(
    workspace_id: Optional[str],
    user_id: Optional[str],
    template_name: Optional[str],
    provider: str,
    model: str,
    tokens_in: int,
    tokens_out: int,
    latency_ms: int,
    status_code: int,
    endpoint: Optional[str] = None
):
    """Persist usage record to database (non-blocking best-effort)"""
    request_id = str(uuid.uuid4())[:8]

    try:
        with get_db_connection() as conn:
            if conn is None:
                logger.debug("Database not available, skipping persistence")
                return

            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO provisioning.ai_usage
                    (workspace_id, user_id, template_name, provider, model,
                     tokens_in, tokens_out, latency_ms, status_code, endpoint, request_id)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    workspace_id, user_id, template_name, provider, model,
                    tokens_in, tokens_out, latency_ms, status_code, endpoint, request_id
                ))
                conn.commit()
                logger.debug(f"Usage persisted: {request_id}")
    except Exception as e:
        logger.warning(f"Failed to persist usage: {e}")

# Initialize FastAPI
app = FastAPI(
    title="AI Gateway",
    description="Multi-provider AI API proxy for secure development environments",
    version="1.0.0"
)

# Rate limiter
limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter

# CORS middleware - SECURITY: Restrict origins in production
cors_origins = ALLOWED_ORIGINS if ALLOWED_ORIGINS and ALLOWED_ORIGINS[0] else [
    "http://localhost:7080",
    "http://host.docker.internal:7080",
    "http://coder-server:7080"
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type", "X-Workspace-ID", "X-User-ID", "X-Template-Name", "X-API-Key", "X-Provider"],
)

# Models with validation
ALLOWED_MODELS = [
    "claude-3-opus", "claude-3-sonnet", "claude-3-haiku",
    "claude-sonnet-4-5-20250929", "claude-haiku-4-5-20251001", "claude-opus-4-20250514",
    "anthropic.claude-3-sonnet", "anthropic.claude-3-haiku",
    "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
    "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "us.anthropic.claude-opus-4-20250514-v1:0"
]

class MessageRequest(BaseModel):
    model: str
    messages: list
    max_tokens: Optional[int] = 1024
    temperature: Optional[float] = 0.7
    stream: Optional[bool] = False

    @validator('model')
    def validate_model(cls, v):
        # Allow any model that starts with known prefixes or is in allowed list
        if v in ALLOWED_MODELS or any(v.startswith(prefix) for prefix in ['claude', 'anthropic', 'us.anthropic']):
            return v
        raise ValueError(f"Model '{v}' not allowed. Use a Claude model.")

    @validator('max_tokens')
    def validate_max_tokens(cls, v):
        if v is not None and (v < 1 or v > 4096):
            raise ValueError("max_tokens must be between 1 and 4096")
        return v

    @validator('temperature')
    def validate_temperature(cls, v):
        if v is not None and (v < 0.0 or v > 2.0):
            raise ValueError("temperature must be between 0.0 and 2.0")
        return v

    @validator('messages')
    def validate_messages(cls, v):
        if not v or len(v) == 0:
            raise ValueError("messages cannot be empty")
        if len(v) > 100:
            raise ValueError("too many messages (max 100)")
        # Check total content length
        total_length = sum(len(str(m.get('content', ''))) for m in v if isinstance(m, dict))
        if total_length > 100000:
            raise ValueError("total message content too long (max 100000 chars)")
        return v

class UsageResponse(BaseModel):
    today: Dict[str, int]
    limit: Dict[str, int]

# In-memory usage tracking (use Redis in production)
usage_tracker: Dict[str, Dict[str, int]] = {}

def track_usage(user: str, tokens_in: int, tokens_out: int):
    """Track API usage per user"""
    today = datetime.now().strftime("%Y-%m-%d")
    key = f"{user}:{today}"
    if key not in usage_tracker:
        usage_tracker[key] = {"requests": 0, "tokens_in": 0, "tokens_out": 0}
    usage_tracker[key]["requests"] += 1
    usage_tracker[key]["tokens_in"] += tokens_in
    usage_tracker[key]["tokens_out"] += tokens_out

def log_request(
    workspace_id: str,
    provider: str,
    model: str,
    tokens_in: int,
    tokens_out: int,
    latency_ms: int,
    status: int,
    user_id: Optional[str] = None,
    template_name: Optional[str] = None,
    endpoint: Optional[str] = None
):
    """Audit log for AI requests (console + database)"""
    # Console logging
    logger.info(json.dumps({
        "event": "ai_request",
        "timestamp": datetime.utcnow().isoformat(),
        "workspace_id": workspace_id,
        "user_id": user_id,
        "template_name": template_name,
        "provider": provider,
        "model": model,
        "tokens_in": tokens_in,
        "tokens_out": tokens_out,
        "latency_ms": latency_ms,
        "status": status
    }))

    # Persist to database
    persist_usage(
        workspace_id=workspace_id if workspace_id != "anonymous" else None,
        user_id=user_id,
        template_name=template_name,
        provider=provider,
        model=model,
        tokens_in=tokens_in,
        tokens_out=tokens_out,
        latency_ms=latency_ms,
        status_code=status,
        endpoint=endpoint
    )

# ============================================================================
# Health & Info Endpoints
# ============================================================================

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    providers_status = {
        "anthropic": bool(os.getenv("ANTHROPIC_API_KEY")),
        "bedrock": bool(os.getenv("AWS_ACCESS_KEY_ID")),
        "gemini": bool(os.getenv("GOOGLE_API_KEY"))
    }
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "providers": providers_status
    }

@app.get("/v1/providers")
async def list_providers():
    """List available AI providers and their status"""
    return {
        "providers": [
            {
                "name": "anthropic",
                "enabled": bool(os.getenv("ANTHROPIC_API_KEY")),
                "models": ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"]
            },
            {
                "name": "bedrock",
                "enabled": bool(os.getenv("AWS_ACCESS_KEY_ID")),
                "models": ["anthropic.claude-3-sonnet", "amazon.titan-text"]
            },
            {
                "name": "gemini",
                "enabled": bool(os.getenv("GOOGLE_API_KEY")),
                "models": ["gemini-pro"]
            }
        ]
    }

@app.get("/v1/usage")
async def get_usage(x_workspace_id: Optional[str] = Header(None)):
    """Get usage statistics for the current user"""
    user = x_workspace_id or "anonymous"
    today = datetime.now().strftime("%Y-%m-%d")
    key = f"{user}:{today}"

    current = usage_tracker.get(key, {"requests": 0, "tokens_in": 0, "tokens_out": 0})

    # Get limits from config
    default_limits = config.get("rate_limits", {}).get("default", {})
    rpm = default_limits.get("requests_per_minute", 60) * 60 * 24  # Daily
    tpm = default_limits.get("tokens_per_minute", 100000) * 60 * 24

    return {
        "today": current,
        "limit": {
            "requests_remaining": max(0, rpm - current["requests"]),
            "tokens_remaining": max(0, tpm - current["tokens_in"] - current["tokens_out"])
        }
    }

# ============================================================================
# Anthropic Claude API Proxy
# ============================================================================

@app.api_route("/v1/claude/{path:path}", methods=["GET", "POST", "PUT", "DELETE"])
@limiter.limit("60/minute")
async def proxy_claude(
    request: Request,
    path: str,
    auth: Dict[str, Any] = Depends(verify_workspace_token),
    x_user_id: Optional[str] = Header(None),
    x_template_name: Optional[str] = Header(None)
):
    """Proxy requests to Anthropic Claude API. Requires authentication."""
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        raise HTTPException(status_code=503, detail="Anthropic API not configured")

    workspace = auth.get("workspace_id", "anonymous")
    start_time = time.time()

    # Build target URL
    target_url = f"https://api.anthropic.com/{path}"

    # Get request body if present
    body = None
    if request.method in ["POST", "PUT"]:
        body = await request.body()

    # Forward headers (excluding hop-by-hop)
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json"
    }

    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            response = await client.request(
                method=request.method,
                url=target_url,
                content=body,
                headers=headers
            )

        latency_ms = int((time.time() - start_time) * 1000)

        # Parse response for logging
        try:
            resp_data = response.json()
            tokens_in = resp_data.get("usage", {}).get("input_tokens", 0)
            tokens_out = resp_data.get("usage", {}).get("output_tokens", 0)
        except:
            tokens_in, tokens_out = 0, 0

        # Track and log
        track_usage(workspace, tokens_in, tokens_out)
        log_request(
            workspace_id=workspace,
            provider="anthropic",
            model="claude",
            tokens_in=tokens_in,
            tokens_out=tokens_out,
            latency_ms=latency_ms,
            status=response.status_code,
            user_id=x_user_id,
            template_name=x_template_name,
            endpoint=f"/v1/claude/{path}"
        )

        return JSONResponse(
            content=response.json(),
            status_code=response.status_code
        )

    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Upstream timeout")
    except Exception as e:
        logger.error(f"Claude proxy error: {str(e)}")
        raise HTTPException(status_code=502, detail=str(e))

# ============================================================================
# AWS Bedrock API Proxy
# ============================================================================

@app.post("/v1/bedrock/invoke")
@limiter.limit("60/minute")
async def invoke_bedrock(
    request: Request,
    auth: Dict[str, Any] = Depends(verify_workspace_token),
    x_user_id: Optional[str] = Header(None),
    x_template_name: Optional[str] = Header(None)
):
    """Invoke AWS Bedrock models. Requires authentication."""
    if not os.getenv("AWS_ACCESS_KEY_ID"):
        raise HTTPException(status_code=503, detail="AWS Bedrock not configured")

    workspace = auth.get("workspace_id", "anonymous")
    start_time = time.time()

    body = await request.json()
    model_id = body.get("model_id", "anthropic.claude-3-sonnet-20240229-v1:0")
    prompt_body = body.get("body", {})

    try:
        # Initialize Bedrock client
        client = boto3.client(
            "bedrock-runtime",
            region_name=os.getenv("AWS_REGION", "us-east-1")
        )

        # Invoke model
        response = client.invoke_model(
            modelId=model_id,
            body=json.dumps(prompt_body)
        )

        # Parse response
        response_body = json.loads(response["body"].read())

        latency_ms = int((time.time() - start_time) * 1000)

        # Extract token usage if available
        tokens_in = response_body.get("usage", {}).get("input_tokens", 0)
        tokens_out = response_body.get("usage", {}).get("output_tokens", 0)

        # Track and log
        track_usage(workspace, tokens_in, tokens_out)
        log_request(
            workspace_id=workspace,
            provider="bedrock",
            model=model_id,
            tokens_in=tokens_in,
            tokens_out=tokens_out,
            latency_ms=latency_ms,
            status=200,
            user_id=x_user_id,
            template_name=x_template_name,
            endpoint="/v1/bedrock/invoke"
        )

        return response_body

    except client.exceptions.ThrottlingException:
        raise HTTPException(status_code=429, detail="Bedrock rate limited")
    except Exception as e:
        logger.error(f"Bedrock invoke error: {str(e)}")
        raise HTTPException(status_code=502, detail=str(e))

@app.get("/v1/bedrock/models")
async def list_bedrock_models():
    """List available Bedrock models"""
    if not os.getenv("AWS_ACCESS_KEY_ID"):
        raise HTTPException(status_code=503, detail="AWS Bedrock not configured")

    try:
        client = boto3.client(
            "bedrock",
            region_name=os.getenv("AWS_REGION", "us-east-1")
        )
        response = client.list_foundation_models()

        return {
            "models": [
                {
                    "id": m["modelId"],
                    "name": m.get("modelName", m["modelId"]),
                    "provider": m.get("providerName", "unknown")
                }
                for m in response.get("modelSummaries", [])
            ]
        }
    except Exception as e:
        logger.error(f"Bedrock list models error: {str(e)}")
        raise HTTPException(status_code=502, detail=str(e))

# ============================================================================
# Google Gemini API Proxy (Planned)
# ============================================================================

@app.api_route("/v1/gemini/{path:path}", methods=["GET", "POST"])
async def proxy_gemini(request: Request, path: str):
    """Proxy requests to Google Gemini API (planned)"""
    api_key = os.getenv("GOOGLE_API_KEY")
    if not api_key:
        raise HTTPException(
            status_code=503,
            detail="Google Gemini API not configured (planned feature)"
        )

    # TODO: Implement Gemini proxy when ready
    raise HTTPException(status_code=501, detail="Gemini support coming soon")

# ============================================================================
# Unified Chat Endpoint (Provider Abstraction)
# ============================================================================

@app.post("/v1/chat/completions")
@limiter.limit("60/minute")
async def unified_chat(
    request: MessageRequest,
    req: Request,
    auth: Dict[str, Any] = Depends(verify_workspace_token),
    x_user_id: Optional[str] = Header(None),
    x_template_name: Optional[str] = Header(None),
    x_provider: Optional[str] = Header("anthropic")
):
    """
    Unified chat endpoint that routes to the appropriate provider.
    Compatible with OpenAI API format for easy integration.
    Requires authentication via Bearer token or X-API-Key.
    """
    workspace = auth.get("workspace_id", "anonymous")
    context = {
        "workspace_id": workspace,
        "user_id": auth.get("user_id") or x_user_id,
        "template_name": x_template_name,
        "authenticated": auth.get("authenticated", False)
    }

    # Route to appropriate provider
    if x_provider == "anthropic" or request.model.startswith("claude"):
        return await _chat_anthropic(request, context)
    elif x_provider == "bedrock" or request.model.startswith("anthropic."):
        return await _chat_bedrock(request, context)
    elif x_provider == "gemini" or request.model.startswith("gemini"):
        raise HTTPException(status_code=501, detail="Gemini support coming soon")
    else:
        raise HTTPException(status_code=400, detail=f"Unknown provider: {x_provider}")

async def _chat_anthropic(request: MessageRequest, context: Dict[str, Any]):
    """Route chat to Anthropic"""
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        raise HTTPException(status_code=503, detail="Anthropic not configured")

    start_time = time.time()

    async with httpx.AsyncClient(timeout=120.0) as client:
        response = await client.post(
            "https://api.anthropic.com/v1/messages",
            headers={
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json"
            },
            json={
                "model": request.model,
                "messages": request.messages,
                "max_tokens": request.max_tokens,
                "temperature": request.temperature
            }
        )

    latency_ms = int((time.time() - start_time) * 1000)
    resp_data = response.json()

    tokens_in = resp_data.get("usage", {}).get("input_tokens", 0)
    tokens_out = resp_data.get("usage", {}).get("output_tokens", 0)

    track_usage(context["workspace_id"], tokens_in, tokens_out)
    log_request(
        workspace_id=context["workspace_id"],
        provider="anthropic",
        model=request.model,
        tokens_in=tokens_in,
        tokens_out=tokens_out,
        latency_ms=latency_ms,
        status=response.status_code,
        user_id=context["user_id"],
        template_name=context["template_name"],
        endpoint="/v1/chat/completions"
    )

    return resp_data

async def _chat_bedrock(request: MessageRequest, context: Dict[str, Any]):
    """Route chat to AWS Bedrock"""
    if not os.getenv("AWS_ACCESS_KEY_ID"):
        raise HTTPException(status_code=503, detail="Bedrock not configured")

    start_time = time.time()

    client = boto3.client(
        "bedrock-runtime",
        region_name=os.getenv("AWS_REGION", "us-east-1")
    )

    # Convert to Bedrock format
    bedrock_body = {
        "anthropic_version": "bedrock-2023-05-31",
        "messages": request.messages,
        "max_tokens": request.max_tokens,
        "temperature": request.temperature
    }

    response = client.invoke_model(
        modelId=request.model,
        body=json.dumps(bedrock_body)
    )

    response_body = json.loads(response["body"].read())
    latency_ms = int((time.time() - start_time) * 1000)

    tokens_in = response_body.get("usage", {}).get("input_tokens", 0)
    tokens_out = response_body.get("usage", {}).get("output_tokens", 0)

    track_usage(context["workspace_id"], tokens_in, tokens_out)
    log_request(
        workspace_id=context["workspace_id"],
        provider="bedrock",
        model=request.model,
        tokens_in=tokens_in,
        tokens_out=tokens_out,
        latency_ms=latency_ms,
        status=200,
        user_id=context["user_id"],
        template_name=context["template_name"],
        endpoint="/v1/chat/completions"
    )

    return response_body

# ============================================================================
# Error Handlers
# ============================================================================

@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(
        status_code=429,
        content={
            "error": "rate_limit_exceeded",
            "message": "Too many requests. Please wait and try again.",
            "retry_after": 60
        }
    )

# ============================================================================
# Main
# ============================================================================

if __name__ == "__main__":
    port = int(os.getenv("AI_GATEWAY_PORT", "8090"))
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")
