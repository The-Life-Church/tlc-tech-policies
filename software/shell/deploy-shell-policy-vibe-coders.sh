#!/bin/bash

# The Life Church — Shell Policy Deployment (Vibe Coders)
#
# ===== What to put in Mosyle =================================================
#   Mosyle -> Scripts (Custom Command) -> new shell script
#     Name:   TLC Shell Policy — Vibe Coders
#     Run:    Recurring     As: root     Scope: vibe coder device group
#     Script:
#       #!/bin/bash
#       curl -fsSL https://raw.githubusercontent.com/The-Life-Church/tlc-tech-policies/main/software/shell/deploy-shell-policy-vibe-coders.sh | bash
# =============================================================================

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
  if [[ "$1" == "exec" ]]; then
    _tlc_run_message; return 1
  fi
  command npm "$@"
}

# Package runners — these download AND execute code from the npm registry in
# one step, which is the same supply-chain surface as an install. Blocked in
# interactive shells; npm scripts and git hooks run non-interactively and are
# unaffected.
_tlc_run_message() {
  echo "Heads up — this command downloads and runs software from the internet,"
  echo "which is handled by IT on this device. If a project needs it, enter a"
  echo "Systems Request at staff.thelifechurch.com and we'll get you moving."
}

npx() {
  _tlc_run_message; return 1
}

bunx() {
  _tlc_run_message; return 1
}

pnpm() {
  if [[ "$1" == "install" && "$#" -gt 1 ]]; then
    _tlc_install_message; return 1
  fi
  if [[ "$1" == "add" || "$1" == "dlx" ]]; then
    _tlc_install_message; return 1
  fi
  command pnpm "$@"
}

yarn() {
  if [[ "$1" == "add" || "$1" == "dlx" ]]; then
    _tlc_install_message; return 1
  fi
  command yarn "$@"
}

bun() {
  if [[ "$1" == "install" && "$#" -gt 1 ]]; then
    _tlc_install_message; return 1
  fi
  if [[ "$1" == "add" || "$1" == "x" ]]; then
    _tlc_install_message; return 1
  fi
  command bun "$@"
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
