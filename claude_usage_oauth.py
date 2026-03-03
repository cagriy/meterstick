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

import json
import os
import subprocess
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Optional

# Constants
KEYCHAIN_SERVICE = "Claude Code-credentials"
OAUTH_API_URL = "https://api.anthropic.com/api/oauth/usage"
CACHE_FILE = Path("/tmp/claude-oauth-usage-cache.json")
CACHE_TTL_SECONDS = 30  # Cache results for 30 seconds
API_TIMEOUT_SECONDS = 2


def get_oauth_token() -> Optional[str]:
    """
    Extract OAuth access token from macOS Keychain.

    Returns:
        Access token string, or None if not found/error
    """
    try:
        # Query keychain for Claude Code credentials
        result = subprocess.run(
            ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True,
            text=True,
            timeout=2
        )

        if result.returncode != 0:
            return None

        # Parse JSON credential structure
        credentials_json = result.stdout.strip()
        credentials = json.loads(credentials_json)

        # Navigate to access token: {"claudeAiOauth": {"accessToken": "sk-ant-oat01-..."}}
        oauth_data = credentials.get("claudeAiOauth", {})
        access_token = oauth_data.get("accessToken")

        if not access_token or not access_token.startswith("sk-ant-oat01-"):
            return None

        return access_token

    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, json.JSONDecodeError, KeyError):
        return None
    except Exception:
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


def get_cached_usage() -> Optional[dict]:
    """
    Load cached usage data if fresh (< CACHE_TTL_SECONDS old).

    Returns:
        Cached usage data, or None if stale/missing
    """
    try:
        if not CACHE_FILE.exists():
            return None

        with open(CACHE_FILE, 'r') as f:
            cache = json.load(f)

        # Check freshness
        cached_time = cache.get("timestamp", 0)
        age = time.time() - cached_time

        if age > CACHE_TTL_SECONDS:
            return None

        return cache.get("data")

    except (json.JSONDecodeError, KeyError, OSError):
        return None


def save_to_cache(data: dict):
    """
    Atomically save usage data to cache using tmp+mv pattern.

    Args:
        data: Usage data dict to cache
    """
    try:
        cache_data = {
            "timestamp": time.time(),
            "data": data
        }

        # Atomic write: tmp file + mv
        tmp_file = CACHE_FILE.with_suffix(f".tmp.{os.getpid()}")
        with open(tmp_file, 'w') as f:
            json.dump(cache_data, f)

        tmp_file.replace(CACHE_FILE)

    except OSError:
        # Silently fail on cache write errors
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
    """
    Main entry point for OAuth usage monitoring.

    Outputs:
        On success: "SUCCESS:5h_util|5h_secs|7d_util|7d_secs"
        On failure: exit code 1, no output
    """
    try:
        # Try cache first
        usage_data = get_cached_usage()

        # If cache miss, fetch from API
        if usage_data is None:
            access_token = get_oauth_token()
            if access_token is None:
                sys.exit(1)

            usage_data = fetch_usage_data(access_token)
            if usage_data is None:
                sys.exit(1)

            # Cache the result
            save_to_cache(usage_data)

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
