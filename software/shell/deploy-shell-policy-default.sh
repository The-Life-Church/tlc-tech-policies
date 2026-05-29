#!/bin/bash

# The Life Church — Shell Policy Deployment (Default)
#
# ===== What to put in Mosyle =================================================
#   Mosyle -> Scripts (Custom Command) -> new shell script
#     Name:   TLC Shell Policy — Default
#     Run:    Recurring     As: root     Scope: default (Claude Code users) device group
#     Script:
#       #!/bin/bash
#       curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/shell/deploy-shell-policy-default.sh | bash
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
