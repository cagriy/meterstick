# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A meterstick package for Claude Code that displays model info, directory, git branch, context usage, and rate limit tracking. The main script (`meterstick.sh`) receives JSON on stdin from Claude Code and outputs ANSI-colored text to stdout.

To test with the installed copy: `bash ~/.claude/meterstick-command.sh`

After editing `meterstick.sh`, copy to install location to see changes live:
```bash
cp meterstick.sh ~/.claude/meterstick-command.sh
```

## Architecture

**Data flow:** Claude Code → executes `~/.claude/meterstick-command.sh` (300ms debounce) → receives JSON stdin → outputs ANSI text → displayed in Claude Code UI.

**Rate limit strategy:** Primary: OAuth via `claude_usage_oauth.py` (real Anthropic API data, 30s cache). Fallback: local token tracking in `~/.claude/usage_tracking.json` against configured limits.

### Key files

- `meterstick.sh` — Core script. Parses input JSON, computes all data, renders configurable sections. Installed to `~/.claude/meterstick-command.sh`.
- `claude_usage_oauth.py` — Python 3 OAuth client. Reads token from macOS Keychain, calls Anthropic API, caches 30s. Called by `fetch_oauth_usage()` in meterstick.sh.
- `install.sh` — 8-step interactive installer. Creates config, installs scripts, updates `~/.claude/settings.json`.
- `uninstall.sh` — Clean removal tool.

### Config files (runtime)

- `~/.claude/meterstick-config.json` — Plan, fallback limits, section order
- `~/.claude/usage_tracking.json` — Session token history (shared with Claude Code)
- `/tmp/claude-meterstick-cache/` — 5s git status cache (md5-keyed by directory)

## Conventions

- **Section rendering:** Each meterstick section has a `render_<name>()` function. Section order/visibility is controlled by the `sections` array in config. Valid names: `model`, `directory`, `git`, `context`, `ratelimits`.
- **Color definitions:** Use `$'\033[...'` syntax (not double-quoted) for proper escape interpretation. Colors are defined as `C_*` variables at the top of meterstick.sh.
- **Null safety:** All values extracted from JSON must be guarded against `"null"` and empty strings before use. Never use `// empty` in jq inside `@json` — it causes the entire output to be empty. Use null passthrough and handle downstream.
- **Caching:** Git info cached 5s per directory. OAuth cached 30s. Atomic writes via tmp+mv pattern.
- **Dependencies:** jq, git, bc (required); Python 3 (optional for OAuth).
