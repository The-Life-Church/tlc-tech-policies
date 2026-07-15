#!/bin/bash

# The Life Church — Shell Policy Deployment (Default)
#
# ===== Mosyle ================================================================
#   Paste-ready block: this folder's README.
#   Name: TLC Shell Policy — Default · root · recurring · scope: default (Claude Code users) device group
#   Does: deploys the full-block Terminal policy (/etc/tlc-shell-policy.zsh wired into /etc/zshrc) — installs no tools
# =============================================================================

POLICY_FILE="/etc/tlc-shell-policy.zsh"
ZSHRC="/etc/zshrc"
SOURCE_LINE="source $POLICY_FILE"

cat > "$POLICY_FILE" << 'EOF'
# The Life Church — Shell Policy (Default)
# Managed by IT. Deployed via Mosyle. Do not edit directly.
# Full terminal restriction for non-developer staff.

echo "Terminal access is restricted on this device."
echo "This Mac is set up for general staff use — the terminal is managed by IT"
echo "to keep things secure and prevent accidental system changes."
echo ""
echo "If you need something specific done, enter a Systems Request at staff.thelifechurch.com"
echo "and IT can help get it taken care of."
exit 0
EOF

chmod 644 "$POLICY_FILE"
chown root:wheel "$POLICY_FILE"

echo "Shell policy (default) deployed to $POLICY_FILE"

if grep -qF "$SOURCE_LINE" "$ZSHRC"; then
    echo "Shell policy already wired into $ZSHRC — nothing to do."
else
    printf "\n# TLC Managed Shell Policy\n%s\n" "$SOURCE_LINE" >> "$ZSHRC"
    echo "Shell policy wired into $ZSHRC."
fi
