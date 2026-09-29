#!/bin/bash
# Runs on first boot via cloud-init (as root).
# Logs to /var/log/setup-vm.log for post-boot inspection.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
exec > /var/log/setup-vm.log 2>&1

echo "[setup-vm] Starting at $(date)"

MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
echo "[setup-vm] $(uname -m), ${MEM_MB} MB RAM"

# ── Swap (npm global installs OOM on 1 GB E2.1.Micro without it) ─────────────
# Skipped on A1.Flex: with 24 GB RAM, swap on a network block volume only adds latency.
if [ "$MEM_MB" -lt 4096 ] && [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
  echo "[setup-vm] 2 GB swap enabled"
fi

# ── System update ────────────────────────────────────────────────────────────
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt-get install -y curl ca-certificates gnupg git build-essential

# ── GitHub CLI ──────────────────────────────────────────────────────────────
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
apt-get update -y
apt-get install -y gh

echo "[versions] gh=$(gh --version | head -1)"

# ── Git defaults for the ubuntu user ────────────────────────────────────────
# Rewrite every HTTPS GitHub URL to SSH at git layer. So even repos cloned via
# HTTPS push over SSH — no credential prompts, no PAT expiry. post-setup.sh
# generates the SSH key + uploads to GitHub via `gh`.
sudo -u ubuntu git config --global init.defaultBranch main
sudo -u ubuntu git config --global url."git@github.com:".insteadOf "https://github.com/"

# Pre-trust github.com host key so the first ssh attempt doesn't prompt
sudo -u ubuntu mkdir -p /home/ubuntu/.ssh
sudo -u ubuntu ssh-keyscan -t ed25519,rsa github.com >> /home/ubuntu/.ssh/known_hosts 2>/dev/null
sudo -u ubuntu sort -u /home/ubuntu/.ssh/known_hosts -o /home/ubuntu/.ssh/known_hosts
chmod 600 /home/ubuntu/.ssh/known_hosts

# SSH config skeleton — post-setup.sh fills in IdentityFile after key gen
if ! grep -q "Host github.com" /home/ubuntu/.ssh/config 2>/dev/null; then
  cat >> /home/ubuntu/.ssh/config <<'CFG'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/github_vm
  IdentitiesOnly yes
CFG
  chown ubuntu:ubuntu /home/ubuntu/.ssh/config
  chmod 600 /home/ubuntu/.ssh/config
fi

# ── Node.js 20 LTS ──────────────────────────────────────────────────────────
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

echo "[versions] node=$(node --version) npm=$(npm --version)"

# ── Bun (required by @kolisachint/hoocowork postinstall) ────────────────────
npm install -g bun
echo "[versions] bun=$(bun --version)"

# ── CLI tools (global npm installs) ─────────────────────────────────────────
echo "[install] @kolisachint/hoocowork"
npm install -g @kolisachint/hoocowork
# hoocowork ships its bin without the executable bit; systemd ExecStart needs it
chmod +x /usr/lib/node_modules/@kolisachint/hoocowork/dist-server/server/cli.js

echo "[install] @anthropic-ai/claude-code (Claude CLI)"
npm install -g @anthropic-ai/claude-code

echo "[install] @openai/codex (Codex CLI)"
npm install -g @openai/codex

echo "[install] opencode-ai (Opencode CLI)"
npm install -g opencode-ai

echo "[install] @kolisachint/hoocode-agent (Hoocode Agent)"
npm install -g @kolisachint/hoocode-agent

# Verify all five are installed
echo "[verify] installed global packages:"
npm list -g --depth=0

# ── Firewall: open 80 + 443 (Caddy); hoocowork on 8080 stays loopback-only ───
# Ubuntu's INPUT chain has a terminal REJECT, so omitting an ACCEPT for 8080
# is enough to keep it unreachable from the public internet.
iptables -I INPUT 5 -p tcp --dport 80  -j ACCEPT
iptables -I INPUT 5 -p tcp --dport 443 -j ACCEPT
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
apt-get install -y iptables-persistent
netfilter-persistent save

# ── Caddy: HTTPS termination via nip.io (auto Let's Encrypt cert) ────────────
# nip.io is on the Public Suffix List, so each subdomain gets its own ACME
# rate-limit bucket. sslip.io shares one bucket and is often exhausted.
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  > /etc/apt/sources.list.d/caddy-stable.list
apt-get update -y
apt-get install -y caddy

# Wait for public IP to be assigned (reserved IP attaches shortly after boot)
PUBLIC_IP=""
for i in $(seq 1 30); do
  PUBLIC_IP=$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)
  [ -n "$PUBLIC_IP" ] && break
  sleep 2
done
HOST="${PUBLIC_IP//./-}.nip.io"
echo "[caddy] HTTPS hostname: $HOST"

cat > /etc/caddy/Caddyfile <<CADDY
${HOST} {
    encode gzip
    reverse_proxy localhost:8080
}
CADDY
systemctl enable caddy
systemctl restart caddy

# ── Unattended security upgrades ─────────────────────────────────────────────
apt-get install -y unattended-upgrades apt-listchanges
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AU'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AU
systemctl enable --now unattended-upgrades

# ── SSH hardening ────────────────────────────────────────────────────────────
# Disable password auth (key-only), forbid root login, cap auth retries
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'SSHC'
PasswordAuthentication no
PermitRootLogin no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
MaxAuthTries 3
LoginGraceTime 30
SSHC
sshd -t && systemctl reload ssh

# ── Systemd service: hoocowork on port 8080 ──────────────────────────────────
# Restart=always + OOMPolicy=continue: if the kernel OOM-kills node, systemd
# would otherwise treat it as a clean stop and leave it down.
# MemoryMax keeps headroom for sshd: 800M on the 1 GB Micro, half of RAM on A1.
if [ "$MEM_MB" -lt 4096 ]; then
  HOOCOWORK_MEMORY_MAX=800M
else
  HOOCOWORK_MEMORY_MAX="$((MEM_MB / 2))M"
fi
cat > /etc/systemd/system/hoocowork.service << EOF
[Unit]
Description=Hoocowork Server
After=network.target
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=simple
User=ubuntu
Environment=PORT=8080
ExecStart=/usr/bin/hoocowork --port 8080
Restart=always
RestartSec=5
OOMPolicy=continue
MemoryMax=${HOOCOWORK_MEMORY_MAX}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hoocowork
systemctl restart hoocowork || echo "[setup-vm] WARNING: hoocowork service failed to start — check: journalctl -u hoocowork"

# ── Health/restart helper: `hoocowork-health` and `hoocowork-health restart` ──
cat > /usr/local/bin/hoocowork-health << 'EOF'
#!/bin/bash
# Usage:
#   hoocowork-health              # show service + system health
#   hoocowork-health restart      # restart the service
#   hoocowork-health logs [N]     # tail N (default 50) log lines
#   hoocowork-health upgrade      # run nightly upgrade now (all CLIs)
set -e
cmd="${1:-status}"
case "$cmd" in
  restart)
    sudo systemctl restart hoocowork
    sleep 2
    systemctl --no-pager status hoocowork | head -20
    ;;
  logs)
    journalctl -u hoocowork -n "${2:-50}" --no-pager
    ;;
  upgrade)
    echo "── starting upgrade-clis.service (this may take 2-5 min) ──"
    sudo systemctl start upgrade-clis.service
    journalctl -u upgrade-clis.service -n 50 --no-pager
    ;;
  status|*)
    echo "── service ───────────────────────────────────────────"
    systemctl --no-pager status hoocowork | head -15
    echo
    echo "── port 8080 ─────────────────────────────────────────"
    ss -tlnp 2>/dev/null | grep ':8080' || echo "  (not listening)"
    echo
    echo "── http health ───────────────────────────────────────"
    curl -fsS -o /dev/null -w "  HTTP %{http_code} in %{time_total}s\n" \
      http://localhost:8080/ || echo "  (no response)"
    echo
    echo "── memory ────────────────────────────────────────────"
    free -h
    echo
    echo "── recent OOM kills ──────────────────────────────────"
    sudo dmesg -T 2>/dev/null | grep -i -E 'killed process|out of memory' | tail -5 \
      || echo "  (none)"
    ;;
esac
EOF
chmod +x /usr/local/bin/hoocowork-health

# ── Nightly CLI auto-upgrade (systemd timer) ─────────────────────────────────
# Runs all `npm install -g <pkg>@latest` overnight (~03:00 UTC + jitter).
# Restarts hoocowork only if its version actually changed.
cat > /usr/local/bin/upgrade-clis << 'UPG'
#!/bin/bash
set -euo pipefail
PACKAGES=(
  "@kolisachint/hoocowork"
  "@kolisachint/hoocode-agent"
  "@anthropic-ai/claude-code"
  "@openai/codex"
  "opencode-ai"
  "bun"
)
echo "[upgrade-clis] starting at $(date -Iseconds)"
HOOCOWORK_BEFORE=$(npm list -g --depth=0 --json 2>/dev/null \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("dependencies",{}).get("@kolisachint/hoocowork",{}).get("version","none"))' \
  || echo none)
for pkg in "${PACKAGES[@]}"; do
  echo "[upgrade-clis] $pkg"
  npm install -g "${pkg}@latest" --silent || echo "[upgrade-clis] WARN: $pkg failed"
done
chmod +x /usr/lib/node_modules/@kolisachint/hoocowork/dist-server/server/cli.js 2>/dev/null || true
HOOCOWORK_AFTER=$(npm list -g --depth=0 --json 2>/dev/null \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("dependencies",{}).get("@kolisachint/hoocowork",{}).get("version","none"))' \
  || echo none)
if [ "$HOOCOWORK_BEFORE" != "$HOOCOWORK_AFTER" ]; then
  echo "[upgrade-clis] hoocowork: $HOOCOWORK_BEFORE -> $HOOCOWORK_AFTER (restarting)"
  systemctl restart hoocowork
else
  echo "[upgrade-clis] hoocowork unchanged at $HOOCOWORK_AFTER"
fi
echo "[upgrade-clis] done at $(date -Iseconds)"
UPG
chmod +x /usr/local/bin/upgrade-clis

cat > /etc/systemd/system/upgrade-clis.service << 'EOF'
[Unit]
Description=Upgrade all AI CLIs to @latest
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/upgrade-clis
StandardOutput=journal
StandardError=journal
EOF

cat > /etc/systemd/system/upgrade-clis.timer << 'EOF'
[Unit]
Description=Nightly AI CLI upgrade

[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=3600
Persistent=true
Unit=upgrade-clis.service

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now upgrade-clis.timer

# ── Drop next-steps hint for the ubuntu user ─────────────────────────────────
cat > /home/ubuntu/NEXT_STEPS.txt << 'MSGEOF'
VM setup is complete. All CLI tools are installed.

Next: run post-setup to configure git, GitHub, and API keys:

  curl -fsSL https://raw.githubusercontent.com/kolisachint/brainstorm/main/infra/scripts/post-setup.sh | bash

Or check the full guide: docs/install.md (Step 9 onwards)
MSGEOF
chown ubuntu:ubuntu /home/ubuntu/NEXT_STEPS.txt

echo "[setup-vm] Completed successfully at $(date)"
