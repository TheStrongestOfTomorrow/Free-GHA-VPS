#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - localhost.run Tunnel
#  Backup tunnel — no account needed, no binary to download
#  Just SSH into localhost.run and get a public URL
# ============================================================
set -euo pipefail

LOCAL_PORT="${1:-6080}"

echo "🌐 Setting up localhost.run tunnel..."

# ── Kill any existing tunnel ────────────────────────────────
pkill -f "localhost.run" 2>/dev/null || true
pkill -f "ssh -R 80" 2>/dev/null || true
sleep 1

# ── Create tunnel via SSH ──────────────────────────────────
# localhost.run provides free SSH tunneling — no signup
NOHUP_OUTPUT=$(mktemp)

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -R 80:localhost:$LOCAL_PORT \
  -o ServerAliveInterval=60 \
  -o ServerAliveCountMax=3 \
  nokey@localhost.run 2>&1 > "$NOHUP_OUTPUT" &

TUNNEL_PID=$!

# ── Extract URL from SSH output ────────────────────────────
echo "   ⏳ Waiting for tunnel URL..."
TUNNEL_URL=""
MAX_WAIT=20

for i in $(seq 1 $MAX_WAIT); do
  # localhost.run prints the URL in the format:
  # "connect to http://xxxxx.lhr.life"
  TUNNEL_URL=$(grep -oP 'https?://[a-zA-Z0-9.-]+\.lhr\.life' "$NOHUP_OUTPUT" 2>/dev/null | head -1 || true)

  if [ -z "$TUNNEL_URL" ]; then
    TUNNEL_URL=$(grep -oP 'https?://[a-zA-Z0-9.-]+\.localhost\.run' "$NOHUP_OUTPUT" 2>/dev/null | head -1 || true)
  fi

  if [ -n "$TUNNEL_URL" ]; then
    break
  fi

  if ! kill -0 $TUNNEL_PID 2>/dev/null; then
    echo ""
    echo "❌ SSH tunnel failed!"
    cat "$NOHUP_OUTPUT"
    exit 1
  fi

  echo -n "."
  sleep 1
done

echo ""

if [ -z "$TUNNEL_URL" ]; then
  echo "❌ Failed to get localhost.run URL after $MAX_WAIT seconds"
  exit 1
fi

# ── Save for other steps ───────────────────────────────────
echo "TUNNEL_URL=$TUNNEL_URL" >> $GITHUB_ENV
echo "TUNNEL_PID=$TUNNEL_PID" >> $GITHUB_ENV

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🌐 LOCALHOST.RUN TUNNEL ACTIVE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  🔗 VNC URL: ${TUNNEL_URL}/vnc.html"
echo "  🔑 VNC Password: $(cat /tmp/vnc-password.txt 2>/dev/null || echo 'none')"
echo ""
echo "  💡 This is a backup tunnel. If slow, try Cloudflare."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "::notice::🌐 Backup VNC URL: ${TUNNEL_URL}/vnc.html"
