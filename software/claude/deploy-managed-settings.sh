#!/bin/bash

# The Life Church — Claude Code Managed Settings Deployment
#
# ===== What to put in Mosyle =================================================
#   Mosyle -> Scripts (Custom Command) -> new shell script
#     Name:   TLC Claude Code Managed Settings
#     Run:    Recurring daily     As: root     Scope: all Claude Code Macs
#     Script:
#       #!/bin/bash
#       curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/claude/deploy-managed-settings.sh | bash
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
