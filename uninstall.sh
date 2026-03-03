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
PYTHON_SCRIPT="$CLAUDE_DIR/claude_usage_oauth.py"
CACHE_DIR="/tmp/claude-meterstick-cache"
OAUTH_CACHE="/tmp/claude-oauth-usage-cache.json"

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Claude Code Meterstick Package Uninstaller       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# CONFIRMATION
# ============================================================================

echo -e "${YELLOW}This will:${NC}"
echo "  • Remove statusLine configuration from settings.json"
echo "  • Delete $INSTALL_SCRIPT"
echo "  • Delete $PYTHON_SCRIPT"
echo "  • Delete $CONFIG_FILE"
echo "  • Clean cache directories"
echo ""
read -p "Continue? [y/N]: " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Uninstall cancelled.${NC}"
    exit 0
fi

echo ""

# ============================================================================
# REMOVE FROM SETTINGS.JSON
# ============================================================================

echo -e "${YELLOW}[1/7]${NC} Removing statusLine from settings.json..."

if [ -f "$SETTINGS_FILE" ]; then
    # Remove statusLine key from settings
    updated_settings=$(jq 'del(.statusLine)' "$SETTINGS_FILE")
    echo "$updated_settings" > "$SETTINGS_FILE"
    echo -e "${GREEN}✓ Removed from $SETTINGS_FILE${NC}"
else
    echo -e "${BLUE}ℹ Settings file not found, skipping${NC}"
fi

echo ""

# ============================================================================
# DELETE INSTALLED SCRIPT
# ============================================================================

echo -e "${YELLOW}[2/7]${NC} Deleting installed script..."

if [ -f "$INSTALL_SCRIPT" ]; then
    rm "$INSTALL_SCRIPT"
    echo -e "${GREEN}✓ Deleted $INSTALL_SCRIPT${NC}"
else
    echo -e "${BLUE}ℹ Script not found, skipping${NC}"
fi

echo ""

# ============================================================================
# DELETE OAUTH SCRIPT
# ============================================================================

echo -e "${YELLOW}[3/7]${NC} Deleting OAuth script..."

if [ -f "$PYTHON_SCRIPT" ]; then
    rm "$PYTHON_SCRIPT"
    echo -e "${GREEN}✓ Deleted $PYTHON_SCRIPT${NC}"
else
    echo -e "${BLUE}ℹ OAuth script not found${NC}"
fi

echo ""

# ============================================================================
# DELETE CONFIG FILE
# ============================================================================

echo -e "${YELLOW}[4/7]${NC} Deleting configuration file..."

if [ -f "$CONFIG_FILE" ]; then
    rm "$CONFIG_FILE"
    echo -e "${GREEN}✓ Deleted $CONFIG_FILE${NC}"
else
    echo -e "${BLUE}ℹ Config file not found, skipping${NC}"
fi

echo ""

# ============================================================================
# CLEAN CACHE
# ============================================================================

echo -e "${YELLOW}[5/7]${NC} Cleaning cache directories..."

if [ -d "$CACHE_DIR" ]; then
    rm -rf "$CACHE_DIR"
    echo -e "${GREEN}✓ Deleted $CACHE_DIR${NC}"
else
    echo -e "${BLUE}ℹ Cache directory not found${NC}"
fi

# Clean OAuth cache
if [ -f "$OAUTH_CACHE" ]; then
    rm -f "$OAUTH_CACHE" "${OAUTH_CACHE}.tmp."*
    echo -e "${GREEN}✓ Deleted OAuth cache${NC}"
else
    echo -e "${BLUE}ℹ OAuth cache not found${NC}"
fi

echo ""

# ============================================================================
# OPTIONAL: DELETE USAGE DATA
# ============================================================================

echo -e "${YELLOW}[6/7]${NC} Usage tracking data"
echo ""
echo -e "${BLUE}Note:${NC} Usage data is stored in $USAGE_FILE"
echo "      This file is shared with other Claude Code features."
echo "      Uninstalling meterstick does NOT remove this file."
echo ""
echo -e "${BLUE}ℹ Preserved usage data at $USAGE_FILE${NC}"

echo ""

# ============================================================================
# VERIFY UNINSTALLATION
# ============================================================================

echo -e "${YELLOW}[7/7]${NC} Verifying uninstallation..."

cleanup_ok=true

if [ -f "$INSTALL_SCRIPT" ]; then
    echo -e "${RED}✗ Statusline script still exists${NC}"
    cleanup_ok=false
fi

if [ -f "$PYTHON_SCRIPT" ]; then
    echo -e "${RED}✗ OAuth script still exists${NC}"
    cleanup_ok=false
fi

if [ -f "$CONFIG_FILE" ]; then
    echo -e "${RED}✗ Config file still exists${NC}"
    cleanup_ok=false
fi

if [ "$cleanup_ok" = true ]; then
    echo -e "${GREEN}✓ All components removed successfully${NC}"
else
    echo -e "${YELLOW}⚠ Some files could not be removed${NC}"
fi

echo ""

# ============================================================================
# UNINSTALL COMPLETE
# ============================================================================

echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Uninstall Complete!                               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  • Restart Claude Code to remove the meterstick"
echo ""
echo -e "${BLUE}To reinstall:${NC}"
echo "  • Run ./install.sh from the package directory"
echo ""
