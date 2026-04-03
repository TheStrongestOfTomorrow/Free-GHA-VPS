#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Start Desktop Environment
#  Launches Xvfb + XFCE4 for remote access
# ============================================================
set -euo pipefail

RESOLUTION="${1:-1920x1080}"
DEPTH="${2:-24}"

echo "🖥️  Starting virtual display (${RESOLUTION}x${DEPTH})..."

# ── Kill any existing displays ───────────────────────────────
sudo pkill -f Xvfb 2>/dev/null || true
sleep 1

# ── Start Xvfb (virtual framebuffer) ────────────────────────
sudo Xvfb :0 -screen 0 "${RESOLUTION}x${DEPTH}" -ac +extension GLX +render -noreset &>/dev/null &
XVFB_PID=$!
export DISPLAY=:0
sleep 2

if ! kill -0 $XVFB_PID 2>/dev/null; then
  echo "❌ Failed to start Xvfb"
  exit 1
fi
echo "✅ Xvfb started (PID: $XVFB_PID) at ${RESOLUTION}"

# ── Start D-Bus (required for XFCE) ─────────────────────────
if [ -z "$(pgrep dbus-daemon)" ]; then
  dbus-launch --exit-with-session &>/dev/null &
  sleep 1
fi

# ── Start XFCE4 desktop session ─────────────────────────────
echo "🖥️  Starting XFCE4 desktop..."
nohup startxfce4 &>/dev/null &
XFCE_PID=$!
sleep 3

if kill -0 $XFCE_PID 2>/dev/null; then
  echo "✅ XFCE4 desktop started (PID: $XFCE_PID)"
else
  echo "⚠️  XFCE4 may have started with a different process tree"
fi

# ── Restart CRD to detect the display ───────────────────────
echo "🔄 Restarting CRD to detect display..."
sudo pkill -f chrome-remote-desktop 2>/dev/null || true
sleep 2
nohup chrome-remote-desktop --start &>/dev/null || true
sleep 3

echo ""
echo "✅ Desktop environment is live at ${RESOLUTION}"
echo "   You should now see this machine in your Google Remote Desktop."
