#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Setup Tailscale
#  Creates a WireGuard VPN link — real RDP quality, no ports
#  Needs TS_AUTHKEY secret for auto-authentication
# ============================================================
set -euo pipefail

CACHE_DIR="/tmp/vps-cache"

echo "🦎 Setting up Tailscale..."

# ── Download Tailscale ─────────────────────────────────────
if command -v tailscale &>/dev/null; then
  echo "   ✅ Tailscale already installed"
else
  # Try cache first
  if [ -f "$CACHE_DIR/tailscale_latest.tgz" ]; then
    echo "   ✅ Restoring Tailscale from cache..."
    sudo tar -xzf "$CACHE_DIR/tailscale_latest.tgz" -C / 2>/dev/null || {
      rm -f "$CACHE_DIR/tailscale_latest.tgz"
      CACHE_DIR=""
    }
  fi

  if [ ! -z "${CACHE_DIR:-}" ] && [ ! -f "$CACHE_DIR/tailscale_latest.tgz" ] && ! command -v tailscale &>/dev/null; then
    echo "   ⬇️  Downloading Tailscale..."
    curl -sL -o "$CACHE_DIR/tailscale_latest.tgz" \
      https://pkgs.tailscale.com/stable/tailscale_latest_amd64.tgz
    sudo tar -xzf "$CACHE_DIR/tailscale_latest.tgz" -C /
    echo "   ✅ Tailscale installed"
  elif ! command -v tailscale &>/dev/null; then
    echo "   ⬇️  Downloading Tailscale..."
    curl -sL -o /tmp/tailscale_latest.tgz \
      https://pkgs.tailscale.com/stable/tailscale_latest_amd64.tgz
    sudo tar -xzf /tmp/tailscale_latest.tgz -C /
    if [ -d "$CACHE_DIR" ]; then
      cp /tmp/tailscale_latest.tgz "$CACHE_DIR/" 2>/dev/null || true
    fi
    echo "   ✅ Tailscale installed"
  fi
fi

# ── Authenticate ────────────────────────────────────────────
TS_KEY="${TS_AUTHKEY:-}"

if [ -z "$TS_KEY" ]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  🔑 TAILSCALE AUTH KEY REQUIRED"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  To use Tailscale + RDP, you need an auth key:"
  echo ""
  echo "  1. Sign up at https://login.tailscale.com/start"
  echo "  2. Go to Settings → Keys → Generate auth key"
  echo "  3. Check 'Reusable' and 'Ephemeral'"
  echo "  4. Copy the key"
  echo "  5. Add it as a GitHub secret named TS_AUTHKEY"
  echo "  6. Re-run this workflow with connection = xrdp-tailscale"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "::notice::🔑 Tailscale needs TS_AUTHKEY secret. See workflow logs."
  exit 1
fi

# Restore Tailscale state if we have it (same device, no re-auth)
# Fixed: tar was created with -C /tmp, so the file is ts-state-tmp.tgz (not home/.tailscale-state.tgz)
if [ -f /tmp/restore-data/ts-state-tmp.tgz ]; then
  echo "   ♻️  Restoring Tailscale state..."
  sudo mkdir -p /var/lib/tailscale
  sudo tar -xzf /tmp/restore-data/ts-state-tmp.tgz -C /var/lib/tailscale 2>/dev/null || true
fi

# Start and authenticate Tailscale
echo "   🦎 Connecting to Tailscale network..."
sudo tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
TS_DAEMON_PID=$!
sleep 3

sudo tailscale up --authkey="$TS_KEY" --accept-routes 2>&1 || {
  echo "   ⚠️  Tailscale auth may have failed, retrying..."
  sleep 3
  sudo tailscale up --authkey="$TS_KEY" --accept-routes 2>&1 || true
}

sleep 5

# ── Get Tailscale IP ───────────────────────────────────────
TS_IP=$(sudo tailscale ip 2>/dev/null || echo "")
TS_HOSTNAME=$(sudo tailscale status 2>/dev/null | grep -oP '^\S+' | head -1 || echo "unknown")

if [ -z "$TS_IP" ]; then
  echo "❌ Failed to get Tailscale IP!"
  echo "   Tailscale may not be connected. Check your auth key."
  sudo tailscale status 2>&1 || true
  exit 1
fi

echo "   ✅ Connected to Tailscale!"

# ── Save state for next run ────────────────────────────────
sudo tar -czf /tmp/tailscale-state-save.tgz -C /var/lib tailscale/ 2>/dev/null || true
sudo mkdir -p /tmp/restore-data
cp /tmp/tailscale-state-save.tgz /tmp/restore-data/ 2>/dev/null || true

# ── Save for other steps ───────────────────────────────────
echo "TS_IP=$TS_IP" >> $GITHUB_ENV
echo "TS_HOSTNAME=$TS_HOSTNAME" >> $GITHUB_ENV
echo "TS_DAEMON_PID=$TS_DAEMON_PID" >> $GITHUB_ENV

RDP_PASS=$(cat /tmp/rdp-password.txt 2>/dev/null || echo "runner")

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🦎 TAILSCALE RDP IS READY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  🌐 Tailscale IP: $TS_IP"
echo "  📛 Hostname: $TS_HOSTNAME"
echo "  🖥️  RDP Port: 3389"
echo "  👤 Username: runner"
echo "  🔑 Password: $RDP_PASS"
echo ""
echo "  📋 How to connect:"
echo "  1. Install Tailscale on your device: https://tailscale.com/download"
echo "  2. Log in with the same Tailscale account"
echo "  3. Open RDP client (Windows: mstsc, Mac: Microsoft Remote Desktop)"
echo "  4. Connect to: $TS_IP"
echo "  5. Enter: runner / $RDP_PASS"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "::notice::🦎 RDP via Tailscale: $TS_IP:3389 | User: runner | Pass: $RDP_PASS"
