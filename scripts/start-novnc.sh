#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Start noVNC
#  Launches x11vnc, websockify, and noVNC web client
#  Call this AFTER start-desktop.sh
# ============================================================
set -euo pipefail

NOVNC_DIR="/opt/noVNC"
VNC_PORT=5900
NOVNC_PORT=6080

echo "🖥️  Starting noVNC..."

# ── Verify display is running ───────────────────────────────
if ! pgrep -f "Xvfb" > /dev/null; then
  echo "❌ Xvfb is not running! Start the desktop first."
  exit 1
fi
echo "   ✅ Xvfb display detected"

# ── Start x11vnc (VNC server attached to :0 display) ──────
echo "   🚀 Starting x11vnc on display :0..."

# Kill any existing x11vnc
pkill -f "x11vnc" 2>/dev/null || true
sleep 1

# Get VNC password - build the correct args
VNC_PASS_FILE="$HOME/.vnc/passwd"
VNC_PASS_ARGS=""
NOPW_FLAG="-nopw"  # Default: no password required
if [ -f "$VNC_PASS_FILE" ]; then
  VNC_PASS_ARGS="-rfbauth $VNC_PASS_FILE"
  NOPW_FLAG=""  # Don't use -nopw when we have a password file
fi

# Start x11vnc
x11vnc \
  -display :0 \
  -rfbport $VNC_PORT \
  $VNC_PASS_ARGS \
  -forever \
  -shared \
  $NOPW_FLAG \
  -noxdamage \
  -nowf \
  -nowcr \
  -nocursorshape \
  -cursor arrow \
  -threads \
  -scale_cur 1 \
  > /tmp/x11vnc.log 2>&1 &

X11VNC_PID=$!
sleep 2

if ! kill -0 $X11VNC_PID 2>/dev/null; then
  echo "❌ x11vnc failed to start!"
  echo "   Logs:"
  cat /tmp/x11vnc.log
  exit 1
fi
echo "   ✅ x11vnc running (PID: $X11VNC_PID, port: $VNC_PORT)"

# ── Start websockify (WebSocket → TCP proxy) + noVNC ──────
echo "   🚀 Starting websockify + noVNC on port $NOVNC_PORT..."

# Kill any existing websockify
pkill -f "websockify" 2>/dev/null || true
sleep 1

# Find websockify binary
WEBSOCKIFY_BIN=""
if command -v websockify &>/dev/null; then
  WEBSOCKIFY_BIN="websockify"
elif [ -f "$NOVNC_DIR/utils/websockify/run" ]; then
  WEBSOCKIFY_BIN="$NOVNC_DIR/utils/websockify/run"
elif [ -f "$NOVNC_DIR/utils/novnc_proxy" ]; then
  # Use noVNC's built-in launcher
  WEBSOCKIFY_BIN="$NOVNC_DIR/utils/novnc_proxy"
fi

if [ -z "$WEBSOCKIFY_BIN" ]; then
  echo "❌ websockify not found!"
  exit 1
fi

# Start noVNC with websockify
nohup $WEBSOCKIFY_BIN \
  --web "$NOVNC_DIR" \
  $NOVNC_PORT \
  localhost:$VNC_PORT \
  > /tmp/novnc.log 2>&1 &

NOVNC_PID=$!
sleep 2

if ! kill -0 $NOVNC_PID 2>/dev/null; then
  echo "❌ noVNC/websockify failed to start!"
  echo "   Logs:"
  cat /tmp/novnc.log
  exit 1
fi
echo "   ✅ noVNC running (PID: $NOVNC_PID, port: $NOVNC_PORT)"

# ── Save connection info ───────────────────────────────────
VNC_PASS=$(cat /tmp/vnc-password.txt 2>/dev/null || echo "none")
echo "NOVNC_PORT=$NOVNC_PORT" >> "${GITHUB_ENV:-/dev/null}"
echo "NOVNC_PID=$NOVNC_PID" >> "${GITHUB_ENV:-/dev/null}"
echo "X11VNC_PID=$X11VNC_PID" >> "${GITHUB_ENV:-/dev/null}"

echo ""
echo "✅ noVNC is live on port $NOVNC_PORT!"
echo "   A tunnel URL will be provided separately."
echo "   VNC Password: $VNC_PASS"
