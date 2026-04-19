#!/bin/bash

# Claude Code Meterstick - Displays model, dir, git, context, and rate limit tracking
# Receives JSON on stdin, outputs ANSI-colored text to stdout

# ============================================================================
# CONFIGURATION
# ============================================================================

CONFIG_FILE="$HOME/.claude/meterstick-config.json"
USAGE_FILE="$HOME/.claude/usage_tracking.json"
CACHE_DIR="/tmp/claude-meterstick-cache"

# Color definitions (using $'...' for proper escape sequence interpretation)
C_RESET=$'\033[0m'
C_BOLD_ORANGE=$'\033[1;38;5;208m'
C_WHITE=$'\033[0;37m'
C_GREEN=$'\033[32m'
C_RED=$'\033[31m'
C_CYAN=$'\033[36m'
C_LIGHT_GRAY=$'\033[38;5;250m'
C_GRAY=$'\033[38;5;245m'
C_DARK_GRAY=$'\033[38;5;240m'
C_YELLOW=$'\033[38;5;178m'
C_BOLD_RED=$'\033[1;38;5;131m'

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Format token numbers (e.g., 3700 -> "3.7K", 1900000 -> "1.9M")
format_tokens() {
    local num="$1"

    # Handle null or empty input
    if [ -z "$num" ] || [ "$num" = "null" ]; then
        echo "0"
        return
    fi

    if [ "$num" -ge 1000000 ]; then
        printf "%.1fM" "$(echo "scale=1; $num/1000000" | bc)"
    elif [ "$num" -ge 1000 ]; then
        printf "%.1fK" "$(echo "scale=1; $num/1000" | bc)"
    else
        echo "$num"
    fi
}

# Format percentage with color coding
format_percentage() {
    local pct="$1"
    local pct_int=${pct%.*}  # Remove decimal part for comparison

    # Handle empty or invalid input
    if [ -z "$pct_int" ] || [ "$pct_int" = "null" ]; then
        pct_int=0
    fi

    if [ "$pct_int" -ge 75 ]; then
        printf "${C_RED}%d%%${C_RESET}" "$pct_int"
    elif [ "$pct_int" -ge 50 ]; then
        printf "${C_YELLOW}%d%%${C_RESET}" "$pct_int"
    else
        printf "${C_LIGHT_GRAY}%d%%${C_RESET}" "$pct_int"
    fi
}

# Format time duration (seconds -> human readable)
format_duration() {
    local secs="$1"
    if [ "$secs" -le 0 ]; then
        echo "0m"
        return
    fi

    local days=$((secs / 86400))
    local hours=$(((secs % 86400) / 3600))
    local mins=$(((secs % 3600) / 60))

    if [ "$days" -gt 0 ]; then
        printf "%dd%dh" "$days" "$hours"
    elif [ "$hours" -gt 0 ]; then
        printf "%dh%dm" "$hours" "$mins"
    else
        printf "%dm" "$mins"
    fi
}

# ============================================================================
# RENDER FUNCTIONS (for configurable section order)
# ============================================================================

# Render model name (bold orange)
render_model() {
    printf "${C_BOLD_ORANGE}%s${C_RESET}" "$model_name"
}

# Render directory path (white)
render_directory() {
    printf "${C_DARK_GRAY}| ${C_WHITE}%s${C_RESET}" "$dir_display"
}

# Render git branch (color-coded, only if in repo)
render_git() {
    if [ -n "$git_info" ]; then
        printf "%s" "$git_info"
    fi
}

# Render context window info (always shown, defaults to 0 if unavailable)
render_context() {
    local pct="${ctx_pct}"
    local in_tokens="${total_in}"
    local out_tokens="${total_out}"
    [ "$pct" = "null" ] || [ -z "$pct" ] && pct=0
    [ "$in_tokens" = "null" ] || [ -z "$in_tokens" ] && in_tokens=0
    [ "$out_tokens" = "null" ] || [ -z "$out_tokens" ] && out_tokens=0
    printf "${C_DARK_GRAY}| ${C_CYAN}▤${C_RESET}%s " "$(format_percentage $pct)"
    printf "${C_CYAN}↑${C_RESET}${C_GRAY}%s${C_RESET} " "$(format_tokens $in_tokens)"
    printf "${C_CYAN}↓${C_RESET}${C_GRAY}%s${C_RESET}" "$(format_tokens $out_tokens)"
}

# Render rate limits (5h and weekly)
render_ratelimits() {
    printf "${C_DARK_GRAY}| ${C_CYAN}5h${C_RESET}:%s/${C_GRAY}%s${C_RESET} " \
        "$(format_percentage $pct_5h)" "$(format_duration $time_5h)"
    printf "${C_CYAN}1w${C_RESET}:%s/${C_GRAY}%s${C_RESET}" \
        "$(format_percentage $pct_weekly)" "$(format_duration $time_weekly)"
    [ "$ratelimits_source" = "oauth" ] && printf " ${C_DARK_GRAY}*${C_RESET}"
}

# Parse model display name (e.g., "claude-opus-4-6" -> "Opus 4.6")
parse_model_name() {
    local model_id="$1"

    # Handle null or empty input
    if [ -z "$model_id" ] || [ "$model_id" = "null" ]; then
        echo "---"
        return
    fi

    # Handle model ID format: claude-{name}-{major}-{minor}
    if [[ "$model_id" =~ claude-([a-z]+)-([0-9]+)-([0-9]+) ]]; then
        local name="${BASH_REMATCH[1]}"
        local major="${BASH_REMATCH[2]}"
        local minor="${BASH_REMATCH[3]}"

        # Capitalize first letter
        name="$(tr '[:lower:]' '[:upper:]' <<< ${name:0:1})${name:1}"
        echo "$name $major.$minor"
    else
        # Fallback to model_id as-is if it doesn't match expected format
        echo "$model_id"
    fi
}

# Format directory as Parent/Current (replace /Users/username with ~)
format_directory() {
    local path="$1"
    # Get just the current directory name (basename)
    basename "$path"
}

# Get git branch with caching (5-second cache)
get_git_info() {
    local dir="$1"
    local cache_key=$(echo -n "$dir" | md5)
    local cache_file="$CACHE_DIR/$cache_key"
    local now=$(date +%s)

    # Check cache validity
    if [ -f "$cache_file" ]; then
        local cache_time=$(stat -f %m "$cache_file" 2>/dev/null || echo 0)
        if [ $((now - cache_time)) -lt 5 ]; then
            cat "$cache_file"
            return
        fi
    fi

    # Compute git info
    cd "$dir" 2>/dev/null || return
    /usr/bin/git rev-parse --is-inside-work-tree &>/dev/null || return

    local branch=$(/usr/bin/git symbolic-ref --short HEAD 2>/dev/null)
    [ -z "$branch" ] && return

    local status=$(/usr/bin/git --no-optional-locks status --porcelain 2>/dev/null)
    local result

    if [ -z "$status" ]; then
        result="${C_GREEN}($branch)${C_RESET}"
    else
        result="${C_RED}($branch)${C_RESET}"
    fi

    # Update cache
    mkdir -p "$CACHE_DIR"
    printf "%s" "$result" > "$cache_file"
    printf "%s" "$result"
}

# Fetch OAuth usage data from Python script
fetch_oauth_usage() {
    local python_script="$HOME/.claude/claude_usage_oauth.py"

    # Check if script exists
    [ ! -f "$python_script" ] && return 1

    # Call Python script (has built-in 2-second timeout)
    local oauth_data
    oauth_data=$(python3 "$python_script" --statusline 2>/dev/null)
    [ $? -ne 0 ] && return 1

    # Parse JSON with jq
    local success=$(echo "$oauth_data" | jq -r '.success // false')
    [ "$success" != "true" ] && return 1

    # Extract values
    local pct_5h=$(echo "$oauth_data" | jq -r '.five_hour.utilization')
    local time_5h=$(echo "$oauth_data" | jq -r '.five_hour.reset_seconds')
    local pct_7d=$(echo "$oauth_data" | jq -r '.seven_day.utilization')
    local time_7d=$(echo "$oauth_data" | jq -r '.seven_day.reset_seconds')

    # Validate all values are present
    if [ "$pct_5h" = "null" ] || [ "$time_5h" = "null" ] || [ "$pct_7d" = "null" ] || [ "$time_7d" = "null" ]; then
        return 1
    fi

    echo "$pct_5h|$time_5h|$pct_7d|$time_7d"
    return 0
}


# ============================================================================
# MAIN LOGIC
# ============================================================================

# Read and parse input JSON in a single jq call
input=$(cat)

data=$(echo "$input" | jq -r '
    {
        model_id: .model.id,
        model_display: .model.display_name,
        cwd: .workspace.current_dir,
        session_id: .session_id,
        ctx_pct: .context_window.used_percentage,
        total_in: .context_window.total_input_tokens,
        total_out: .context_window.total_output_tokens,
        rl_5h_pct: .rate_limits.five_hour.used_percentage,
        rl_5h_resets_at: .rate_limits.five_hour.resets_at,
        rl_7d_pct: .rate_limits.seven_day.used_percentage,
        rl_7d_resets_at: .rate_limits.seven_day.resets_at
    } | @json
')

model_id=$(echo "$data" | jq -r '.model_id')
model_display=$(echo "$data" | jq -r '.model_display')
cwd=$(echo "$data" | jq -r '.cwd')
session_id=$(echo "$data" | jq -r '.session_id')
ctx_pct=$(echo "$data" | jq -r '.ctx_pct')
total_in=$(echo "$data" | jq -r '.total_in')
total_out=$(echo "$data" | jq -r '.total_out')
rl_5h_pct=$(echo "$data" | jq -r '.rl_5h_pct')
rl_5h_resets_at=$(echo "$data" | jq -r '.rl_5h_resets_at')
rl_7d_pct=$(echo "$data" | jq -r '.rl_7d_pct')
rl_7d_resets_at=$(echo "$data" | jq -r '.rl_7d_resets_at')

# Parse model name
if [ "$model_display" != "null" ] && [ -n "$model_display" ]; then
    model_name="$model_display"
elif [ "$model_id" != "null" ] && [ -n "$model_id" ]; then
    model_name=$(parse_model_name "$model_id")
else
    # Model info not yet available (startup or mode switch)
    model_name="---"
fi

# Format directory
dir_display=$(format_directory "$cwd")

# Get git info (cached)
git_info=$(get_git_info "$cwd")

# ============================================================================
# USAGE TRACKING
# ============================================================================

# Initialize usage file if missing
if [ ! -f "$USAGE_FILE" ]; then
    echo '{"sessions":[]}' > "$USAGE_FILE"
fi

# Update usage tracking
now=$(date +%s)

if [ "$total_in" != "null" ] && [ "$total_out" != "null" ] && [ -n "$total_in" ] && [ -n "$total_out" ]; then
    # Read current data
    usage_data=$(cat "$USAGE_FILE")

    # Update or add session
    usage_data=$(echo "$usage_data" | jq --arg sid "$session_id" \
        --argjson ts "$now" \
        --argjson tin "$total_in" \
        --argjson tout "$total_out" '
        .sessions = (.sessions | map(select(.session_id != $sid))) + [{
            session_id: $sid,
            timestamp: $ts,
            input_tokens: $tin,
            output_tokens: $tout
        }]
    ')

    # Clean up old sessions (>7 days)
    week_ago=$((now - 604800))
    usage_data=$(echo "$usage_data" | jq --argjson cutoff "$week_ago" \
        '.sessions = (.sessions | map(select(.timestamp >= $cutoff)))')

    # Atomic write (tmp + mv)
    tmp_file="${USAGE_FILE}.tmp.$$"
    echo "$usage_data" > "$tmp_file"
    mv "$tmp_file" "$USAGE_FILE"
fi

# ============================================================================
# RATE LIMIT CALCULATION (native stdin → OAuth fallback)
# ============================================================================

ratelimits_available=false

if [ "$rl_5h_pct" != "null" ] && [ -n "$rl_5h_pct" ] && \
   [ "$rl_7d_pct" != "null" ] && [ -n "$rl_7d_pct" ]; then
    # Native rate limit data from Claude Code stdin
    pct_5h="$rl_5h_pct"
    pct_weekly="$rl_7d_pct"
    now_epoch=$(date +%s)
    if [ "$rl_5h_resets_at" != "null" ] && [ -n "$rl_5h_resets_at" ]; then
        time_5h=$((rl_5h_resets_at - now_epoch))
        [ "$time_5h" -lt 0 ] && time_5h=0
    else
        time_5h=0
    fi
    if [ "$rl_7d_resets_at" != "null" ] && [ -n "$rl_7d_resets_at" ]; then
        time_weekly=$((rl_7d_resets_at - now_epoch))
        [ "$time_weekly" -lt 0 ] && time_weekly=0
    else
        time_weekly=0
    fi
    ratelimits_available=true
    ratelimits_source="native"
else
    # Fallback: OAuth via Python script
    oauth_result=$(fetch_oauth_usage)
    if [ $? -eq 0 ]; then
        pct_5h=$(echo "$oauth_result" | cut -d'|' -f1)
        time_5h=$(echo "$oauth_result" | cut -d'|' -f2)
        pct_weekly=$(echo "$oauth_result" | cut -d'|' -f3)
        time_weekly=$(echo "$oauth_result" | cut -d'|' -f4)
        ratelimits_available=true
        ratelimits_source="oauth"
    fi
fi

# ============================================================================
# SECTION CONFIGURATION
# ============================================================================

# Default section order
DEFAULT_SECTIONS="model directory git context ratelimits"

# Read configured sections from config file
if [ -f "$CONFIG_FILE" ]; then
    configured_sections=$(jq -r '
        if .sections then .sections | join(" ") else empty end
    ' "$CONFIG_FILE" 2>/dev/null)
fi

# Use configured sections or fall back to default
sections="${configured_sections:-$DEFAULT_SECTIONS}"

# Handle empty array case (fall back to default)
if [ -z "$sections" ]; then
    sections="$DEFAULT_SECTIONS"
fi

# ============================================================================
# OUTPUT
# ============================================================================

# Render sections in configured order
first=true
for section in $sections; do
    # Add space separator between sections (except before first)
    [ "$first" = true ] && first=false || printf " "

    # Render the section
    case "$section" in
        model)      render_model ;;
        directory)  render_directory ;;
        git)        render_git ;;
        context)    render_context ;;
        ratelimits) [ "$ratelimits_available" = true ] && render_ratelimits ;;
        *)          ;;  # silently ignore unknown section names
    esac
done

echo
