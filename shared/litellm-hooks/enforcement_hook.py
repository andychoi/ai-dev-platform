"""
Design-First Enforcement Hook for LiteLLM Proxy.

Reads enforcement_level from virtual key metadata, prepends
appropriate system prompt to chat completion requests.

Levels: unrestricted | standard | design-first
Prompts loaded from /app/prompts/*.md (editable without restart).
"""

import logging
import os
from pathlib import Path

from litellm.integrations.custom_logger import CustomLogger

log = logging.getLogger("litellm.enforcement")

PROMPTS_DIR = Path(os.environ.get("ENFORCEMENT_PROMPTS_DIR", "/app/prompts"))
DEFAULT_LEVEL = os.environ.get("DEFAULT_ENFORCEMENT_LEVEL", "standard")
VALID_LEVELS = {"unrestricted", "standard", "design-first"}

# File mtime cache: level -> (mtime, content)
_cache: dict[str, tuple[float, str]] = {}


def _load_prompt(level: str) -> str:
    """Load prompt file with mtime-based cache (edit files without restart)."""
    path = PROMPTS_DIR / f"{level}.md"
    if not path.exists():
        log.warning("Prompt file not found: %s", path)
        return ""
    mtime = path.stat().st_mtime
    if level in _cache and _cache[level][0] == mtime:
        return _cache[level][1]
    text = path.read_text().strip()
    _cache[level] = (mtime, text)
    log.info("Loaded prompt: level=%s len=%d", level, len(text))
    return text


class EnforcementHook(CustomLogger):
    """LiteLLM callback that injects enforcement system prompts."""

    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        if call_type not in ("completion", "acompletion"):
            return data

        # Read enforcement_level from key metadata
        meta = getattr(user_api_key_dict, "metadata", {}) or {}
        level = meta.get("enforcement_level", DEFAULT_LEVEL)
        if level not in VALID_LEVELS:
            log.warning("Invalid enforcement_level=%s, using default=%s", level, DEFAULT_LEVEL)
            level = DEFAULT_LEVEL

        # unrestricted = no injection, original tool behavior
        if level == "unrestricted":
            return data

        prompt = _load_prompt(level)
        if not prompt:
            return data

        # Prepend enforcement prompt as first system message
        messages = data.get("messages", [])
        data["messages"] = [{"role": "system", "content": prompt}] + messages
        log.debug("Injected enforcement prompt: level=%s", level)

        return data


# Instance registered in litellm config.yaml via callbacks
proxy_handler_instance = EnforcementHook()
