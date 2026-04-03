#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Cloudflare Quick Tunnel
#  Creates a free public URL to expose noVNC/RDP
#  No account needed, no signup, zero friction
# ============================================================
set -euo pipefail

LOCAL_PORT="${1:-6080}"
CF_DIR="/tmp/cloudflared"

echo "☁️  Setting up Cloudflare Tunnel..."

# ── Download cloudflared ────────────────────────────────────
if [ -f "$CF_DIR/cloudflared" ]; then
  echo "   ✅ cloudflared found"
else
  echo "   ⬇️  Downloading cloudflared..."
  mkdir -p "$CF_DIR"
  curl -sL -o "$CF_DIR/cloudflared" \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  chmod +x "$CF_DIR/cloudflared"
  echo "   ✅ cloudflared downloaded"
fi

# ── Cache cloudflared binary for next run ───────────────────
if [ -d "/tmp/vps-cache" ]; then
  cp "$CF_DIR/cloudflared" /tmp/vps-cache/cloudflared 2>/dev/null || true
fi

# ── Start quick tunnel (no account needed!) ────────────────
echo "   🚀 Creating quick tunnel (localhost:$LOCAL_PORT → internet)..."

pkill -f "cloudflared" 2>/dev/null || true
sleep 1

nohup "$CF_DIR/cloudflared" tunnel \
  --url "http://localhost:$LOCAL_PORT" \
  --no-autoupdate \
  > /tmp/cloudflared.log 2>&1 &

CF_PID=$!

# ── Extract the tunnel URL from logs ───────────────────────
echo "   ⏳ Waiting for tunnel URL..."
TUNNEL_URL=""
MAX_WAIT=30

for i in $(seq 1 $MAX_WAIT); do
  TUNNEL_URL=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1 || true)

  if [ -n "$TUNNEL_URL" ]; then
    break
  fi

  # Check if cloudflared crashed
  if ! kill -0 $CF_PID 2>/dev/null; then
    echo ""
    echo "❌ cloudflared crashed!"
    cat /tmp/cloudflared.log
    exit 1
  fi

  echo -n "."
  sleep 1
done

echo ""

if [ -z "$TUNNEL_URL" ]; then
  echo "❌ Failed to get tunnel URL after $MAX_WAIT seconds"
  echo "   Cloudflare may be blocking this region or runner."
  exit 1
fi

# ── Save for other steps ───────────────────────────────────
echo "TUNNEL_URL=$TUNNEL_URL" >> $GITHUB_ENV
echo "CF_PID=$CF_PID" >> $GITHUB_ENV

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ☁️  CLOUDFLARE TUNNEL ACTIVE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  🔗 VNC URL: ${TUNNEL_URL}/vnc.html"
echo "  📐 Display: $(cat /tmp/vps-resolution.txt 2>/dev/null || echo '1920x1080')"
echo "  🔑 VNC Password: $(cat /tmp/vnc-password.txt 2>/dev/null || echo 'none')"
echo ""
echo "  ⏱️  This tunnel is temporary and expires with the session."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# GitHub Actions annotation (visible in workflow UI)
echo "::notice::☁️ VNC URL: ${TUNNEL_URL}/vnc.html | Password: $(cat /tmp/vnc-password.txt 2>/dev/null || echo 'none')"
