#!/usr/bin/env python3
"""
Claude Code OAuth Usage Monitor

Retrieves real-time rate limit utilization from Anthropic's OAuth API.
Falls back gracefully on any error (exit code 1) so meterstick can use local tracking.

Usage:
    python3 claude_usage_oauth.py --statusline

    On success: JSON output with utilization percentages and reset times
    {
        "success": true,
        "five_hour": {"utilization": 16.0, "reset_seconds": 10800},
        "seven_day": {"utilization": 17.0, "reset_seconds": 86400}
    }

    On failure: exit 1 (no output)
"""

import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Optional

OAUTH_API_URL = "https://api.anthropic.com/api/oauth/usage"
CACHE_TTL_SECONDS = 30
API_TIMEOUT_SECONDS = 2


def keychain_service_for(config_dir: str) -> list[str]:
    """Return keychain service name candidates for a config dir, most specific first."""
    suffix = hashlib.sha256(config_dir.encode()).hexdigest()[:8]
    return [f"Claude Code-credentials-{suffix}", "Claude Code-credentials"]


def cache_file_for(config_dir: str) -> Path:
    suffix = hashlib.sha256(config_dir.encode()).hexdigest()[:8]
    return Path(f"/tmp/claude-oauth-usage-cache-{suffix}.json")


def get_oauth_token(service_candidates: list[str]) -> Optional[str]:
    """Extract OAuth access token from macOS Keychain, trying each candidate service name."""
    for service in service_candidates:
        try:
            result = subprocess.run(
                ["security", "find-generic-password", "-s", service, "-w"],
                capture_output=True, text=True, timeout=2
            )
            if result.returncode != 0:
                continue

            credentials = json.loads(result.stdout.strip())
            oauth_data = credentials.get("claudeAiOauth", {})
            access_token = oauth_data.get("accessToken")

            if access_token and access_token.startswith("sk-ant-oat01-"):
                return access_token

        except (subprocess.TimeoutExpired, json.JSONDecodeError, KeyError, Exception):
            continue

    return None


def fetch_usage_data(access_token: str) -> Optional[dict]:
    """
    Call Anthropic OAuth API to retrieve real-time usage data.

    Args:
        access_token: OAuth access token from keychain

    Returns:
        Usage data dict with "five_hour" and "seven_day" keys, or None on error
    """
    try:
        # Build API request
        headers = {
            "Authorization": f"Bearer {access_token}",
            "anthropic-beta": "oauth-2025-04-20"
        }

        request = urllib.request.Request(
            OAUTH_API_URL,
            headers=headers,
            method="GET"
        )

        # Execute with timeout
        with urllib.request.urlopen(request, timeout=API_TIMEOUT_SECONDS) as response:
            if response.status != 200:
                return None

            data = json.loads(response.read().decode('utf-8'))

            # Validate response structure
            if "five_hour" not in data or "seven_day" not in data:
                return None

            # Ensure required fields exist
            for window in ["five_hour", "seven_day"]:
                if "utilization" not in data[window] or "resets_at" not in data[window]:
                    return None

            return data

    except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError, KeyError):
        return None
    except Exception:
        return None


def get_cached_usage(cache_file: Path, allow_stale: bool = False) -> Optional[dict]:
    try:
        if not cache_file.exists():
            return None

        with open(cache_file, 'r') as f:
            cache = json.load(f)

        if not allow_stale:
            if time.time() - cache.get("timestamp", 0) > CACHE_TTL_SECONDS:
                return None

        return cache.get("data")

    except (json.JSONDecodeError, KeyError, OSError):
        return None


def save_to_cache(cache_file: Path, data: dict):
    try:
        tmp_file = cache_file.with_suffix(f".tmp.{os.getpid()}")
        with open(tmp_file, 'w') as f:
            json.dump({"timestamp": time.time(), "data": data}, f)
        tmp_file.replace(cache_file)
    except OSError:
        pass


def parse_reset_time(reset_timestamp: str) -> int:
    """
    Convert ISO 8601 timestamp to seconds remaining.

    Args:
        reset_timestamp: ISO 8601 timestamp string (e.g., "2026-02-14T15:30:00Z")

    Returns:
        Seconds until reset, or 0 if parse error/already passed
    """
    try:
        # Parse ISO 8601 format
        reset_time = datetime.fromisoformat(reset_timestamp.replace('Z', '+00:00'))
        now = datetime.now(reset_time.tzinfo)

        seconds_remaining = int((reset_time - now).total_seconds())
        return max(0, seconds_remaining)

    except (ValueError, AttributeError):
        return 0


def main():
    args = sys.argv[1:]
    config_dir = os.path.expanduser("~/.claude")
    for i, arg in enumerate(args):
        if arg == "--config-dir" and i + 1 < len(args):
            config_dir = os.path.realpath(args[i + 1])

    services = keychain_service_for(config_dir)
    cache_file = cache_file_for(config_dir)

    try:
        usage_data = get_cached_usage(cache_file)

        if usage_data is None:
            access_token = get_oauth_token(services)
            if access_token is None:
                sys.exit(1)

            usage_data = fetch_usage_data(access_token)
            if usage_data is None:
                usage_data = get_cached_usage(cache_file, allow_stale=True)
                if usage_data is None:
                    sys.exit(1)
            else:
                save_to_cache(cache_file, usage_data)

        # Parse data
        five_hour = usage_data["five_hour"]
        seven_day = usage_data["seven_day"]

        # Extract utilization percentages
        util_5h = five_hour["utilization"]
        util_7d = seven_day["utilization"]

        # Parse reset times to seconds remaining
        secs_5h = parse_reset_time(five_hour["resets_at"])
        secs_7d = parse_reset_time(seven_day["resets_at"])

        # Output in JSON format for easy parsing with jq
        result = {
            "success": True,
            "five_hour": {
                "utilization": util_5h,
                "reset_seconds": secs_5h
            },
            "seven_day": {
                "utilization": util_7d,
                "reset_seconds": secs_7d
            }
        }
        print(json.dumps(result))
        sys.exit(0)

    except Exception:
        # Silent failure - statusline will use fallback
        sys.exit(1)


if __name__ == "__main__":
    main()
