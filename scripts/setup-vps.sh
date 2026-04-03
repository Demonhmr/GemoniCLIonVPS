#!/bin/bash
# =============================================================================
# setup-vps.sh — First-time VPS provisioning for Gemini CLI Docker
#
# What this script does (in order):
#   1. System update
#   2. Docker Engine installation
#   3. fail2ban (SSH brute-force protection)
#   4. Unprivileged deploy user creation
#   5. SSH hardening (password auth disabled, root login disabled)
#   6. UFW firewall (port 22 only)
#   7. Clone repo & start container
#
# ⚠️  READ THIS SCRIPT BEFORE RUNNING. Never pipe curl directly to bash.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/GemoniCLIonVPS/main/scripts/setup-vps.sh \
#       -o /tmp/setup-vps.sh
#   cat /tmp/setup-vps.sh        ← inspect first!
#   bash /tmp/setup-vps.sh
#
# Prerequisites:
#   - Run as root on a fresh Ubuntu 22.04 VPS
#   - Your SSH public key must already be in /root/.ssh/authorized_keys
#     (so you can log in as gemini-vps after root login is disabled)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Config — adjust before running
# ---------------------------------------------------------------------------
DEPLOY_USER="gemini-vps"
REPO_DIR="/opt/gemini-cli"
REPO_URL="https://github.com/Demonhmr/GemoniCLIonVPS.git"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo -e "\n\033[1;34m=== $* ===\033[0m"; }
ok()    { echo -e "\033[1;32m✓ $*\033[0m"; }
warn()  { echo -e "\033[1;33m⚠️  $*\033[0m"; }
die()   { echo -e "\033[1;31m✗ FATAL: $*\033[0m" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Guard: must run as root
# ---------------------------------------------------------------------------
[[ $EUID -ne 0 ]] && die "Run this script as root"

# ---------------------------------------------------------------------------
# Guard: SSH public key must exist before we disable password auth
# ---------------------------------------------------------------------------
if [[ ! -s /root/.ssh/authorized_keys ]]; then
    die "No SSH public key found in /root/.ssh/authorized_keys.\nAdd your key first:\n  ssh-copy-id -i ~/.ssh/id_ed25519.pub root@VPS_IP\nThen re-run this script."
fi

# ---------------------------------------------------------------------------
info "1/7 — System update"
# ---------------------------------------------------------------------------
apt-get update -qq && apt-get upgrade -y -qq
ok "System updated"

# ---------------------------------------------------------------------------
info "2/7 — Installing Docker Engine"
# ---------------------------------------------------------------------------
if command -v docker &>/dev/null; then
    ok "Docker already installed: $(docker --version)"
else
    # Install via apt (avoids curl|sh) — official Docker apt repo
    apt-get install -y -qq ca-certificates gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker --now
    ok "Docker installed: $(docker --version)"
fi

# ---------------------------------------------------------------------------
info "3/7 — Installing fail2ban (SSH brute-force protection)"
# ---------------------------------------------------------------------------
apt-get install -y -qq ufw fail2ban
systemctl enable fail2ban --now
ok "fail2ban active"

# ---------------------------------------------------------------------------
info "4/7 — Creating unprivileged deploy user: $DEPLOY_USER"
# ---------------------------------------------------------------------------
if ! id "$DEPLOY_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$DEPLOY_USER"
    ok "User $DEPLOY_USER created"
else
    ok "User $DEPLOY_USER already exists"
fi

# Add to docker group so user can run docker commands without sudo
usermod -aG docker "$DEPLOY_USER"
ok "$DEPLOY_USER added to docker group"

# Copy SSH authorized_keys from root to new user
mkdir -p /home/"$DEPLOY_USER"/.ssh
cp /root/.ssh/authorized_keys /home/"$DEPLOY_USER"/.ssh/authorized_keys
chown -R "$DEPLOY_USER":"$DEPLOY_USER" /home/"$DEPLOY_USER"/.ssh
chmod 700 /home/"$DEPLOY_USER"/.ssh
chmod 600 /home/"$DEPLOY_USER"/.ssh/authorized_keys
ok "SSH key copied to $DEPLOY_USER"

# ---------------------------------------------------------------------------
info "5/7 — SSH hardening"
# ---------------------------------------------------------------------------
SSHD_CONFIG="/etc/ssh/sshd_config"

# Backup original config
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"

# Apply hardening settings
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/'   "$SSHD_CONFIG"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/'                 "$SSHD_CONFIG"
sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/'                     "$SSHD_CONFIG"
sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/'                         "$SSHD_CONFIG"
sed -i 's/^#\?LoginGraceTime.*/LoginGraceTime 20/'                   "$SSHD_CONFIG"
sed -i 's/^#\?AllowAgentForwarding.*/AllowAgentForwarding no/'       "$SSHD_CONFIG"
sed -i 's/^#\?AllowTcpForwarding.*/AllowTcpForwarding no/'           "$SSHD_CONFIG"

# Whitelist only the deploy user
grep -qxF "AllowUsers $DEPLOY_USER" "$SSHD_CONFIG" || \
    echo "AllowUsers $DEPLOY_USER" >> "$SSHD_CONFIG"

# Validate config before reloading
sshd -t || die "sshd config validation failed. Check $SSHD_CONFIG"
# Ubuntu 22.04+: service named 'ssh', older systems: 'sshd'
SSH_SERVICE=$(systemctl list-units --type=service --all | grep -oP '(sshd|ssh)(?=\.service)' | head -1)
systemctl reload "$SSH_SERVICE"
ok "SSH hardened — password login DISABLED, root login DISABLED"
warn "From now on: ssh $DEPLOY_USER@<VPS_IP>"

# ---------------------------------------------------------------------------
info "6/7 — UFW Firewall"
# ---------------------------------------------------------------------------
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw --force enable
ok "UFW enabled — only port 22/tcp open"

# ---------------------------------------------------------------------------
info "7/7 — Clone repository and start container"
# ---------------------------------------------------------------------------
if [[ -d "$REPO_DIR" ]]; then
    warn "$REPO_DIR already exists — pulling latest changes"
    git -C "$REPO_DIR" pull
else
    git clone "$REPO_URL" "$REPO_DIR"
fi

chown -R "$DEPLOY_USER":"$DEPLOY_USER" "$REPO_DIR"

# Start container as deploy user
# newgrp is needed because the docker group assignment requires a new session;
# sg runs a command in the context of the new group without re-login.
sudo -u "$DEPLOY_USER" sg docker -c "cd $REPO_DIR && docker compose up -d --build"
ok "Container started"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
VPS_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "================================================"
echo "  VPS SETUP COMPLETE"
echo "================================================"
echo "  Connect : ssh ${DEPLOY_USER}@${VPS_IP}"
echo "  Repo    : cd ${REPO_DIR}"
echo "------------------------------------------------"
echo "  FIRST-TIME AUTH (run once after connect):"
echo "    make attach"
echo "    # In tmux: type gemini"
echo "    # Open the printed URL in a browser"
echo "    # Complete Google OAuth"
echo "    # Detach: Ctrl+A, D  (session stays alive)"
echo "================================================"
echo ""
