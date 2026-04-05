#!/bin/bash

# The Life Church — Claude Code Policy Deployment
# Deploy via Mosyle as a recurring daily script (run as root)
# Source: https://raw.githubusercontent.com/The-Life-Church/claude-vibe-coder/main/CLAUDE.md

POLICY_DIR="/etc/claude-code"
POLICY_FILE="$POLICY_DIR/CLAUDE.md"
POLICY_URL="https://raw.githubusercontent.com/The-Life-Church/claude-vibe-coder/main/CLAUDE.md"
IMPORT_BLOCK="
# ---------------------------------------------------------------
# TLC MANAGED POLICY — do not remove this block
# Add your own content ABOVE this section, not below.
# This is maintained by IT and updated automatically.
# ---------------------------------------------------------------
@$POLICY_FILE
# ---------------------------------------------------------------"

# Detect the logged-in console user (works on macOS when run as root via MDM)
CONSOLE_USER=$(stat -f "%Su" /dev/console)
USER_HOME=$(dscl . -read /Users/"$CONSOLE_USER" NFSHomeDirectory | awk '{print $2}')
USER_CLAUDE_DIR="$USER_HOME/.claude"
USER_CLAUDE_MD="$USER_CLAUDE_DIR/CLAUDE.md"

# Pull latest policy to /etc/claude-code/
mkdir -p "$POLICY_DIR"
curl -s "$POLICY_URL" -o "$POLICY_FILE"

if [ ! -f "$POLICY_FILE" ]; then
    echo "ERROR: Failed to deploy Claude Code policy."
    exit 1
fi

echo "Claude Code policy deployed successfully."

# Wire the policy into the user's ~/.claude/CLAUDE.md
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ] || [ ! -d "$USER_CLAUDE_DIR" ]; then
    echo "WARNING: Could not configure user policy — ~/.claude/ not found for user $CONSOLE_USER. Claude Code may not have been launched yet on this machine."
    exit 0
fi

if [ -f "$USER_CLAUDE_MD" ]; then
    # File exists — append the block if it isn't already there
    if grep -qF "@$POLICY_FILE" "$USER_CLAUDE_MD"; then
        echo "Policy import already present in $USER_CLAUDE_MD — nothing to do."
    else
        printf "%s" "$IMPORT_BLOCK" >> "$USER_CLAUDE_MD"
        chown "$CONSOLE_USER" "$USER_CLAUDE_MD"
        echo "Policy block appended to existing $USER_CLAUDE_MD."
    fi
else
    # No file yet — create one with just the import block
    printf "%s\n" "$IMPORT_BLOCK" > "$USER_CLAUDE_MD"
    chown "$CONSOLE_USER" "$USER_CLAUDE_MD"
    echo "Created $USER_CLAUDE_MD with policy block."
fi
