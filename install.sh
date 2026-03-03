#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Files and directories
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
CONFIG_FILE="$CLAUDE_DIR/meterstick-config.json"
USAGE_FILE="$CLAUDE_DIR/usage_tracking.json"
INSTALL_SCRIPT="$CLAUDE_DIR/meterstick-command.sh"

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Claude Code Meterstick Package Installer         ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo ""

# ============================================================================
# PREREQUISITES CHECK
# ============================================================================

echo -e "${YELLOW}[1/8]${NC} Checking prerequisites..."

missing_deps=()

if ! command -v jq &> /dev/null; then
    missing_deps+=("jq")
fi

if ! command -v bc &> /dev/null; then
    missing_deps+=("bc")
fi

if [ ${#missing_deps[@]} -ne 0 ]; then
    echo -e "${RED}✗ Missing required dependencies: ${missing_deps[*]}${NC}"
    echo ""
    echo "Install them with:"
    echo "  brew install ${missing_deps[*]}"
    exit 1
fi

echo -e "${GREEN}✓ All required dependencies met${NC}"
echo ""

# Check for git (optional but recommended)
if command -v git &> /dev/null; then
    echo -e "${GREEN}✓ Git found - git branch status will be displayed${NC}"
else
    echo -e "${YELLOW}⚠ Git not found - git section will be hidden${NC}"
fi

# Check for Python (optional but recommended)
python_available=false
python_cmd=""

if command -v python3 &> /dev/null; then
    python_cmd="python3"
    python_version=$(python3 --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    python_available=true
elif command -v python &> /dev/null; then
    # Check if 'python' is Python 3
    python_version=$(python --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    major_version=$(echo "$python_version" | cut -d. -f1)
    if [ "$major_version" -ge 3 ]; then
        python_cmd="python"
        python_available=true
    fi
fi

if [ "$python_available" = true ]; then
    echo -e "${GREEN}✓ Python 3 found (version $python_version)${NC}"
    echo -e "${BLUE}  OAuth real-time monitoring will be enabled${NC}"
else
    echo -e "${YELLOW}⚠ Python 3 not found${NC}"
    echo "  OAuth real-time usage monitoring will be unavailable."
    echo "  Meterstick will use local token tracking instead."
    echo ""
    read -p "Continue without Python? [y/N]: " continue_without_python
    if [[ ! "$continue_without_python" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Install Python 3: brew install python3${NC}"
        exit 1
    fi
fi

echo ""

# ============================================================================
# SET DEFAULT CONFIGURATION
# ============================================================================

echo -e "${YELLOW}[2/8]${NC} Setting up default configuration..."

# Use default sections (all sections in standard order)
sections_array='["model", "directory", "git", "context", "ratelimits"]'

echo -e "${GREEN}✓ Default configuration set${NC}"
echo ""

# ============================================================================
# CREATE CONFIG FILE
# ============================================================================

echo -e "${YELLOW}[3/8]${NC} Creating configuration file..."

mkdir -p "$CLAUDE_DIR"

cat > "$CONFIG_FILE" <<EOF
{
  "sections": $sections_array
}
EOF

echo -e "${GREEN}✓ Config written to $CONFIG_FILE${NC}"
echo ""

# ============================================================================
# INSTALL METERSTICK SCRIPT
# ============================================================================

echo -e "${YELLOW}[4/8]${NC} Installing meterstick script..."

# Get the directory where this install script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ ! -f "$SCRIPT_DIR/meterstick.sh" ]; then
    echo -e "${RED}✗ meterstick.sh not found in $SCRIPT_DIR${NC}"
    exit 1
fi

cp "$SCRIPT_DIR/meterstick.sh" "$INSTALL_SCRIPT"
chmod +x "$INSTALL_SCRIPT"

echo -e "${GREEN}✓ Installed to $INSTALL_SCRIPT${NC}"
echo ""

# ============================================================================
# INSTALL PYTHON OAUTH SCRIPT
# ============================================================================

echo -e "${YELLOW}[5/8]${NC} Installing OAuth integration..."

if [ "$python_available" = true ]; then
    PYTHON_SCRIPT="$CLAUDE_DIR/claude_usage_oauth.py"

    if [ ! -f "$SCRIPT_DIR/claude_usage_oauth.py" ]; then
        echo -e "${RED}✗ claude_usage_oauth.py not found in $SCRIPT_DIR${NC}"
        exit 1
    fi

    cp "$SCRIPT_DIR/claude_usage_oauth.py" "$PYTHON_SCRIPT"
    chmod +x "$PYTHON_SCRIPT"

    # Test OAuth
    echo -e "${BLUE}Testing OAuth keychain access...${NC}"
    test_result=$($python_cmd "$PYTHON_SCRIPT" --statusline 2>&1)

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ OAuth integration working${NC}"
        echo -e "${BLUE}  Using real-time Anthropic API data${NC}"
    else
        echo -e "${YELLOW}⚠ OAuth test failed (will use local tracking)${NC}"
        echo -e "${BLUE}  This is normal if you haven't logged in to Claude Code yet${NC}"
    fi
else
    echo -e "${BLUE}ℹ Skipping OAuth (Python not available)${NC}"
fi

echo ""

# ============================================================================
# UPDATE SETTINGS.JSON
# ============================================================================

echo -e "${YELLOW}[6/8]${NC} Updating Claude Code settings..."

# Create settings.json if it doesn't exist
if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi

# Merge statusLine config into settings.json
updated_settings=$(jq --arg cmd "$INSTALL_SCRIPT" \
    '.statusLine = {
        "type": "command",
        "command": $cmd,
        "debounceMs": 300
    }' "$SETTINGS_FILE")

echo "$updated_settings" > "$SETTINGS_FILE"

echo -e "${GREEN}✓ Updated $SETTINGS_FILE${NC}"
echo ""

# ============================================================================
# INITIALIZE USAGE TRACKING
# ============================================================================

echo -e "${YELLOW}[7/8]${NC} Initializing usage tracking..."

if [ ! -f "$USAGE_FILE" ]; then
    echo '{"sessions":[]}' > "$USAGE_FILE"
    echo -e "${GREEN}✓ Created new usage file${NC}"
else
    echo -e "${BLUE}ℹ Usage file already exists, preserving existing data${NC}"
fi

echo ""

# ============================================================================
# VERIFY INSTALLATION
# ============================================================================

echo -e "${YELLOW}[8/8]${NC} Verifying installation..."

# Check all required files exist
files_ok=true

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}✗ Config file not created${NC}"
    files_ok=false
fi

if [ ! -f "$INSTALL_SCRIPT" ]; then
    echo -e "${RED}✗ Meterstick script not installed${NC}"
    files_ok=false
fi

if [ ! -f "$SETTINGS_FILE" ]; then
    echo -e "${RED}✗ Settings file not found${NC}"
    files_ok=false
fi

if [ "$files_ok" = true ]; then
    echo -e "${GREEN}✓ All files installed correctly${NC}"
else
    echo -e "${RED}✗ Installation verification failed${NC}"
    exit 1
fi

echo ""

# ============================================================================
# INSTALLATION COMPLETE
# ============================================================================

echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Installation Complete!                            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Restart Claude Code to activate the meterstick"
echo "  2. The meterstick will appear after each assistant message"
echo ""
echo -e "${BLUE}Configuration:${NC}"
echo "  • Config file: $CONFIG_FILE"
echo "  • Usage data:  $USAGE_FILE"
echo "  • Script:      $INSTALL_SCRIPT"
echo ""
echo -e "${BLUE}To adjust rate limits:${NC}"
echo "  Edit $CONFIG_FILE"
echo ""
echo -e "${BLUE}To uninstall:${NC}"
echo "  Run ./uninstall.sh"
echo ""
