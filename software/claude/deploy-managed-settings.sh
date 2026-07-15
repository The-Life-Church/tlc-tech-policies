#!/bin/bash

# The Life Church — Claude Code Managed Settings Deployment
#
# ===== Mosyle ================================================================
#   Paste-ready block: this folder's README.
#   Name: TLC Claude Code Managed Settings · root · recurring daily · scope: all Claude Code Macs
#   Does: fetches managed-settings.json (deny rules + force-enabled plugins) to
#   /Library/Application Support/ClaudeCode/ — installs no tools
# =============================================================================
#
# Pulls managed-settings.json from main into /Library/Application Support/ClaudeCode/:
#   https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/claude/managed-settings.json

SETTINGS_DIR="/Library/Application Support/ClaudeCode"
SETTINGS_FILE="$SETTINGS_DIR/managed-settings.json"
SETTINGS_URL="https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/claude/managed-settings.json"

mkdir -p "$SETTINGS_DIR"
curl -s "$SETTINGS_URL" -o "$SETTINGS_FILE"

if [ ! -f "$SETTINGS_FILE" ]; then
    echo "ERROR: Failed to deploy Claude Code managed settings."
    exit 1
fi

chmod 644 "$SETTINGS_FILE"
chown root:wheel "$SETTINGS_FILE"

echo "Claude Code managed settings deployed to $SETTINGS_FILE"
