"""
Content Guardrails Hook for LiteLLM Proxy.

Scans chat completion requests for PII, financial data, secrets,
and sensitive content. Blocks or masks detected patterns before
the request reaches the upstream model provider.

Guardrail levels (stored in key metadata.guardrail_level):
  off        — no scanning (default for unrestricted enforcement)
  standard   — block/mask high-confidence PII/secrets, warn on medium
  strict     — block/mask all detected patterns including medium-confidence

Guardrail action (stored in key metadata.guardrail_action):
  block      — reject request with 400 (default)
  mask       — replace detected patterns with [REDACTED:<label>] and proceed

Patterns are loaded from /app/guardrails/patterns.json (editable without restart).
"""

import json
import logging
import os
import re
from pathlib import Path

from fastapi import HTTPException
from litellm.integrations.custom_logger import CustomLogger

log = logging.getLogger("litellm.guardrails")

GUARDRAILS_DIR = Path(os.environ.get("GUARDRAILS_DIR", "/app/guardrails"))
DEFAULT_GUARDRAIL_LEVEL = os.environ.get("DEFAULT_GUARDRAIL_LEVEL", "standard")
DEFAULT_GUARDRAIL_ACTION = os.environ.get("DEFAULT_GUARDRAIL_ACTION", "block")
GUARDRAILS_ENABLED = os.environ.get("GUARDRAILS_ENABLED", "true").lower() == "true"
VALID_LEVELS = {"off", "standard", "strict"}
VALID_ACTIONS = {"block", "mask"}

# File mtime cache: path -> (mtime, content)
_file_cache: dict[str, tuple[float, object]] = {}


# ---------------------------------------------------------------------------
# Built-in patterns (always available, no external file needed)
# ---------------------------------------------------------------------------

BUILTIN_PATTERNS = {
    # --- PII ---
    "us_ssn": {
        "pattern": r"\b\d{3}-\d{2}-\d{4}\b",
        "label": "US Social Security Number",
        "category": "pii",
        "severity": "high",
        "action": "block",
    },
    "email_address": {
        "pattern": r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b",
        "label": "Email address",
        "category": "pii",
        "severity": "medium",
        "action": "flag",
    },
    "phone_us": {
        "pattern": r"\b(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b",
        "label": "US phone number",
        "category": "pii",
        "severity": "medium",
        "action": "flag",
    },
    "passport_us": {
        "pattern": r"\b[A-Z]\d{8}\b",
        "label": "US passport number",
        "category": "pii",
        "severity": "high",
        "action": "block",
    },

    # --- Financial ---
    "credit_card_visa": {
        "pattern": r"\b4\d{3}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b",
        "label": "Visa credit card number",
        "category": "financial",
        "severity": "high",
        "action": "block",
    },
    "credit_card_mastercard": {
        "pattern": r"\b5[1-5]\d{2}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b",
        "label": "Mastercard credit card number",
        "category": "financial",
        "severity": "high",
        "action": "block",
    },
    "credit_card_amex": {
        "pattern": r"\b3[47]\d{2}[-\s]?\d{6}[-\s]?\d{5}\b",
        "label": "Amex credit card number",
        "category": "financial",
        "severity": "high",
        "action": "block",
    },
    "iban": {
        "pattern": r"\b[A-Z]{2}\d{2}[A-Z0-9]{4}\d{7}([A-Z0-9]?){0,16}\b",
        "label": "IBAN",
        "category": "financial",
        "severity": "high",
        "action": "block",
    },
    "bank_routing_aba": {
        "pattern": r"\b[0-9]{9}\b",
        "label": "Bank routing number (ABA)",
        "category": "financial",
        "severity": "medium",
        "action": "flag",
        "context_required": True,  # Only flag when near financial keywords
    },
    "swift_bic": {
        "pattern": r"\b[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?\b",
        "label": "SWIFT/BIC code",
        "category": "financial",
        "severity": "medium",
        "action": "flag",
        "context_required": True,
    },

    # --- Secrets & Credentials ---
    "aws_access_key": {
        "pattern": r"\bAKIA[0-9A-Z]{16}\b",
        "label": "AWS access key",
        "category": "secret",
        "severity": "high",
        "action": "block",
    },
    "aws_secret_key": {
        "pattern": r"\b[A-Za-z0-9/+=]{40}\b",
        "label": "AWS secret key (candidate)",
        "category": "secret",
        "severity": "medium",
        "action": "flag",
        "context_required": True,
    },
    "github_token": {
        "pattern": r"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{36,}\b",
        "label": "GitHub token",
        "category": "secret",
        "severity": "high",
        "action": "block",
    },
    "generic_api_key": {
        "pattern": r"\b(sk|pk|api|token|secret|key)[-_][A-Za-z0-9]{20,}\b",
        "label": "Generic API key/token",
        "category": "secret",
        "severity": "high",
        "action": "block",
    },
    "private_key_pem": {
        "pattern": r"-----BEGIN\s+(RSA\s+|EC\s+|DSA\s+|OPENSSH\s+)?PRIVATE\s+KEY-----",
        "label": "Private key (PEM)",
        "category": "secret",
        "severity": "high",
        "action": "block",
    },
    "jwt_token": {
        "pattern": r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b",
        "label": "JWT token",
        "category": "secret",
        "severity": "high",
        "action": "block",
    },
    "slack_token": {
        "pattern": r"\bxox[bporas]-[A-Za-z0-9-]{10,}\b",
        "label": "Slack token",
        "category": "secret",
        "severity": "high",
        "action": "block",
    },
    "connection_string": {
        "pattern": r"\b(postgres|mysql|mongodb|redis)://\S+:\S+@\S+",
        "label": "Database connection string with credentials",
        "category": "secret",
        "severity": "high",
        "action": "block",
    },
}

# Financial context keywords — used for context_required patterns
FINANCIAL_CONTEXT_KEYWORDS = {
    "routing", "aba", "swift", "bic", "wire", "transfer",
    "bank", "account", "iban", "sort code", "payment",
}


def _load_custom_patterns() -> dict:
    """Load custom patterns from JSON file with mtime-based caching."""
    path = GUARDRAILS_DIR / "patterns.json"
    if not path.exists():
        return {}

    mtime = path.stat().st_mtime
    cache_key = str(path)
    if cache_key in _file_cache and _file_cache[cache_key][0] == mtime:
        return _file_cache[cache_key][1]

    try:
        raw = json.loads(path.read_text())
        # Filter out metadata keys (e.g. _comment, _format) — only keep pattern dicts
        data = {k: v for k, v in raw.items() if not k.startswith("_") and isinstance(v, dict) and "pattern" in v}
        _file_cache[cache_key] = (mtime, data)
        log.info("Loaded custom patterns: %d patterns", len(data))
        return data
    except Exception as e:
        log.error("Failed to load custom patterns: %s", e)
        return {}


def _get_all_patterns() -> dict:
    """Merge built-in and custom patterns (custom overrides built-in)."""
    patterns = dict(BUILTIN_PATTERNS)
    custom = _load_custom_patterns()
    patterns.update(custom)
    return patterns


def _has_financial_context(text: str) -> bool:
    """Check if text contains financial-related keywords."""
    text_lower = text.lower()
    return any(kw in text_lower for kw in FINANCIAL_CONTEXT_KEYWORDS)


def _scan_text(text: str, level: str) -> list[dict]:
    """
    Scan text for sensitive patterns. Returns list of findings.

    Each finding: {"pattern_name": str, "label": str, "category": str,
                   "severity": str, "action": str, "match": str}
    """
    findings = []
    patterns = _get_all_patterns()

    for name, config in patterns.items():
        # Skip context-required patterns if context not present
        if config.get("context_required") and not _has_financial_context(text):
            continue

        try:
            matches = re.findall(config["pattern"], text, re.IGNORECASE)
        except re.error as e:
            log.warning("Invalid regex for pattern %s: %s", name, e)
            continue

        if not matches:
            continue

        severity = config.get("severity", "medium")
        action = config.get("action", "flag")

        # Level-based filtering
        if level == "standard" and severity == "medium" and action == "flag":
            # Standard: log medium-severity flags but don't block
            for match in matches:
                findings.append({
                    "pattern_name": name,
                    "label": config["label"],
                    "category": config.get("category", "unknown"),
                    "severity": severity,
                    "action": "warn",
                    "match": _redact_match(str(match)),
                })
        elif level == "strict" or action == "block":
            # Strict blocks everything; any level blocks high-severity
            for match in matches:
                findings.append({
                    "pattern_name": name,
                    "label": config["label"],
                    "category": config.get("category", "unknown"),
                    "severity": severity,
                    "action": "block",
                    "match": _redact_match(str(match)),
                })
        else:
            # Flag but allow through
            for match in matches:
                findings.append({
                    "pattern_name": name,
                    "label": config["label"],
                    "category": config.get("category", "unknown"),
                    "severity": severity,
                    "action": "warn",
                    "match": _redact_match(str(match)),
                })

    return findings


def _redact_match(match: str) -> str:
    """Partially redact a match for logging (show first/last 2 chars)."""
    if len(match) <= 6:
        return "***"
    return f"{match[:2]}***{match[-2:]}"


def _extract_text(data: dict) -> str:
    """Extract all user-provided text from the request payload."""
    parts = []
    for msg in data.get("messages", []):
        content = msg.get("content", "")
        if isinstance(content, str):
            parts.append(content)
        elif isinstance(content, list):
            # Multi-modal messages: extract text parts
            for item in content:
                if isinstance(item, dict) and item.get("type") == "text":
                    parts.append(item.get("text", ""))
    return "\n".join(parts)


def _mask_message_content(content, patterns_to_mask: list[dict]) -> tuple:
    """
    Replace detected patterns in message content with [REDACTED:<label>] placeholders.
    Returns (masked_content, mask_count).

    Works with both string content and multi-modal content arrays.
    """
    mask_count = 0

    if isinstance(content, str):
        masked = content
        for p in patterns_to_mask:
            try:
                tag = f"[REDACTED:{p['label']}]"
                masked, n = re.subn(p["pattern"], tag, masked, flags=re.IGNORECASE)
                mask_count += n
            except re.error:
                pass
        return masked, mask_count

    if isinstance(content, list):
        masked_list = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                text = item.get("text", "")
                for p in patterns_to_mask:
                    try:
                        tag = f"[REDACTED:{p['label']}]"
                        text, n = re.subn(p["pattern"], tag, text, flags=re.IGNORECASE)
                        mask_count += n
                    except re.error:
                        pass
                masked_list.append({**item, "text": text})
            else:
                masked_list.append(item)
        return masked_list, mask_count

    return content, 0


def _apply_masking(data: dict, findings: list[dict]) -> int:
    """
    Mask all blocked findings in the request messages in-place.
    Returns total number of masked occurrences.
    """
    # Build list of patterns to mask (only blockable findings)
    blocks = [f for f in findings if f["action"] == "block"]
    if not blocks:
        return 0

    # Deduplicate by pattern name and collect their regexes
    seen = set()
    patterns_to_mask = []
    all_patterns = _get_all_patterns()
    for finding in blocks:
        name = finding["pattern_name"]
        if name not in seen and name in all_patterns:
            seen.add(name)
            patterns_to_mask.append({
                "pattern": all_patterns[name]["pattern"],
                "label": finding["label"],
            })

    total_masked = 0
    for msg in data.get("messages", []):
        content = msg.get("content")
        if content is not None:
            masked, count = _mask_message_content(content, patterns_to_mask)
            msg["content"] = masked
            total_masked += count

    return total_masked


class GuardrailsHook(CustomLogger):
    """LiteLLM callback that scans requests for PII, financial data, and secrets."""

    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        log.info("Guardrails hook called: call_type=%s enabled=%s", call_type, GUARDRAILS_ENABLED)

        if call_type not in ("completion", "acompletion"):
            return data

        if not GUARDRAILS_ENABLED:
            return data

        # Read guardrail_level and guardrail_action from key metadata
        meta = getattr(user_api_key_dict, "metadata", {}) or {}
        level = meta.get("guardrail_level", DEFAULT_GUARDRAIL_LEVEL)
        action = meta.get("guardrail_action", DEFAULT_GUARDRAIL_ACTION)
        log.info("Guardrails: level=%s action=%s meta_keys=%s", level, action, list(meta.keys()))
        if level not in VALID_LEVELS:
            log.warning("Invalid guardrail_level=%s, using default=%s", level, DEFAULT_GUARDRAIL_LEVEL)
            level = DEFAULT_GUARDRAIL_LEVEL
        if action not in VALID_ACTIONS:
            log.warning("Invalid guardrail_action=%s, using default=%s", action, DEFAULT_GUARDRAIL_ACTION)
            action = DEFAULT_GUARDRAIL_ACTION

        # off = no scanning
        if level == "off":
            return data

        # Extract and scan all user text
        text = _extract_text(data)
        if not text.strip():
            return data

        findings = _scan_text(text, level)
        if not findings:
            return data

        # Separate blocks from warnings
        blocks = [f for f in findings if f["action"] == "block"]
        warnings = [f for f in findings if f["action"] == "warn"]

        # Log warnings (don't block or mask)
        for w in warnings:
            log.warning(
                "Guardrail warning: %s (%s) detected [%s] — match: %s",
                w["label"], w["category"], w["severity"], w["match"],
            )

        # Handle blockable findings based on guardrail_action
        if blocks:
            blocked_labels = ", ".join(sorted(set(b["label"] for b in blocks)))
            blocked_categories = ", ".join(sorted(set(b["category"] for b in blocks)))

            if action == "mask":
                # Mask: replace sensitive patterns in-place and let the request proceed
                mask_count = _apply_masking(data, blocks)
                log.warning(
                    "Guardrail MASKED %d occurrence(s) in request: %s",
                    mask_count, blocked_labels,
                )
            else:
                # Block: reject the request
                log.warning(
                    "Guardrail BLOCKED request: %d pattern(s) detected — %s",
                    len(blocks), blocked_labels,
                )
                raise HTTPException(
                    status_code=400,
                    detail=(
                        f"Request blocked by content guardrails. "
                        f"Detected sensitive data: {blocked_labels}. "
                        f"Categories: {blocked_categories}. "
                        f"Remove sensitive information before sending to AI. "
                        f"Guardrail level: {level}"
                    ),
                )

        return data


# Instance registered in litellm config.yaml via callbacks
guardrails_instance = GuardrailsHook()
