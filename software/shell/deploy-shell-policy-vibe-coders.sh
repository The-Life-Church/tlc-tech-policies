#!/bin/bash

# The Life Church — Shell Policy Deployment (Vibe Coders)
# Deploy via Mosyle as a recurring script (run as root)
# Scope to vibe coder device group in Mosyle.
# curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/shell/deploy-shell-policy-vibe-coders.sh | bash

POLICY_FILE="/etc/tlc-shell-policy.zsh"
ZSHRC="/etc/zshrc"
SOURCE_LINE="source $POLICY_FILE"

cat > "$POLICY_FILE" << 'EOF'
# The Life Church — Shell Policy (Vibe Coders)
# Managed by IT. Deployed via Mosyle. Do not edit directly.

_tlc_install_message() {
  echo "Heads up — package installs are handled by IT."
  echo "Reach out by entering a Systems Request at staff.thelifechurch.com."
}

_tlc_blocked_message() {
  echo "Heads up — that command is restricted on this device."
  echo "Reach out by entering a Systems Request at staff.thelifechurch.com."
}

# Privilege escalation
sudo() {
  _tlc_blocked_message; return 1
}

brew() {
  if [[ "$1" == "install" ]]; then
    _tlc_install_message; return 1
  fi
  command brew "$@"
}

npm() {
  if [[ "$1" == "install" && "$#" -gt 1 ]]; then
    _tlc_install_message; return 1
  fi
  command npm "$@"
}

pip() {
  if [[ "$1" == "install" && "$2" != "-r" && "$#" -gt 1 ]]; then
    _tlc_install_message; return 1
  fi
  command pip "$@"
}

pip3() {
  if [[ "$1" == "install" && "$2" != "-r" && "$#" -gt 1 ]]; then
    _tlc_install_message; return 1
  fi
  command pip3 "$@"
}
EOF

chmod 644 "$POLICY_FILE"
chown root:wheel "$POLICY_FILE"

echo "Shell policy (vibe coders) deployed to $POLICY_FILE"

if grep -qF "$SOURCE_LINE" "$ZSHRC"; then
    echo "Shell policy already wired into $ZSHRC — nothing to do."
else
    printf "\n# TLC Managed Shell Policy\n%s\n" "$SOURCE_LINE" >> "$ZSHRC"
    echo "Shell policy wired into $ZSHRC."
fi
