#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Keepalive Script
#  Keeps the runner active with realistic activity
#  Supports session extension via "Extend VPS Session" workflow
# ============================================================
set -euo pipefail

DURATION="${1:-30}"
# Leave 2 minutes for data save and cleanup
ACTIVE_MINUTES=$((DURATION - 2))
END_TIME=$((SECONDS + (ACTIVE_MINUTES * 60)))
EXTENSION_COUNT=0
MAX_EXTENSIONS=5  # Safety limit

echo "🔄 Keepalive started — will run for ${ACTIVE_MINUTES} minutes"
echo "   Total session: ${DURATION} minutes (2 min reserved for save)"
echo "   Ends at: $(date -d "+${ACTIVE_MINUTES} minutes" '+%H:%M:%S UTC')"
echo "   💡 You can extend by triggering the 'Extend VPS Session' workflow!"
echo ""

INTERVAL=60  # Check every 60 seconds
TICK=0
LAST_CHECKED_BRANCHES=""

check_for_extension() {
  # Check for vps-extend-* signal branches
  SIGNAL_BRANCHES=$(git ls-remote --heads origin 'refs/heads/vps-extend-*' 2>/dev/null || true)

  if [ -z "$SIGNAL_BRANCHES" ]; then
    return 1
  fi

  # Only process branches we haven't seen before
  if [ "$SIGNAL_BRANCHES" = "$LAST_CHECKED_BRANCHES" ]; then
    return 1
  fi

  # Find the newest signal branch
  SIGNAL_BRANCH=$(echo "$SIGNAL_BRANCHES" | head -1 | awk '{print $2}' | sed 's|refs/heads/||')

  # Read the extension amount from the branch
  EXTRA_MINUTES=30  # default
  SIGNAL_DATA=$(git fetch origin "$SIGNAL_BRANCH" 2>/dev/null && git show "origin/$SIGNAL_BRANCH:.vps-extend-signal" 2>/dev/null || true)
  if [ -n "$SIGNAL_DATA" ]; then
    EXTRA_MINUTES=$(echo "$SIGNAL_DATA" | cut -d'|' -f2)
    EXTRA_MINUTES="${EXTRA_MINUTES:-30}"
  fi

  # Cap at 30 min per extension
  if [ "$EXTRA_MINUTES" -gt 30 ]; then
    EXTRA_MINUTES=30
  fi

  # Check extension limit
  if [ $EXTENSION_COUNT -ge $MAX_EXTENSIONS ]; then
    echo "⚠️  Maximum extensions ($MAX_EXTENSIONS) reached. No more extensions allowed."
    LAST_CHECKED_BRANCHES="$SIGNAL_BRANCHES"
    return 1
  fi

  # Delete the signal branch (cleanup)
  git push origin --delete "$SIGNAL_BRANCH" 2>/dev/null || true
  LAST_CHECKED_BRANCHES=""

  # Extend the session
  END_TIME=$((END_TIME + (EXTRA_MINUTES * 60)))
  EXTENSION_COUNT=$((EXTENSION_COUNT + 1))
  TOTAL_REMAINING=$(( (END_TIME - SECONDS) / 60 ))

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ⏰  SESSION EXTENDED! +${EXTRA_MINUTES} minutes"
  echo "  📊 Extensions used: ${EXTENSION_COUNT}/${MAX_EXTENSIONS}"
  echo "  ⏳ New end time: $(date -d "+${TOTAL_REMAINING} minutes" '+%H:%M:%S UTC')"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  return 0
}

while true; do
  # Check if session time is up
  if [ $SECONDS -ge $END_TIME ]; then
    echo ""
    echo "✅ Keepalive completed. Session duration reached."
    echo "   Total extensions used: ${EXTENSION_COUNT}"
    echo "   Proceeding to save persistent data..."
    exit 0
  fi

  TICK=$((TICK + 1))
  REMAINING=$(( (END_TIME - SECONDS) / 60 ))

  # ── Check for extension signals ────────────────────────────
  if [ $((TICK % 3)) -eq 0 ]; then  # Check every 3 minutes
    check_for_extension || true
  fi

  # ── Recalculate remaining time after potential extension ───
  REMAINING=$(( (END_TIME - SECONDS) / 60 ))
  if [ $REMAINING -lt 1 ]; then
    echo ""
    echo "✅ Keepalive completed. Session duration reached."
    echo "   Total extensions used: ${EXTENSION_COUNT}"
    echo "   Proceeding to save persistent data..."
    exit 0
  fi

  # ── Realistic background activity ─────────────────────────

  # Simulate light system usage
  ps aux --sort=-%mem | head -5 > /dev/null 2>&1

  # ── Auto-detect and monitor connection method ─────────────
  # Check which services are running and keep them alive

  # CRD (Chrome Remote Desktop)
  if pgrep -f "chrome-remote-desktop" > /dev/null; then
    : # running
  fi

  # x11vnc (noVNC VNC server)
  if pgrep -f "x11vnc" > /dev/null; then
    : # running
  elif [ -f /tmp/vnc-password.txt ]; then
    echo "⚠️  x11vnc stopped! Restarting..."
    nohup x11vnc -display :0 -rfbport 5900 -forever -shared -nopw \
      > /tmp/x11vnc.log 2>&1 &
    sleep 2
  fi

  # websockify/noVNC
  if pgrep -f "websockify" > /dev/null; then
    : # running
  elif pgrep -f "novnc_proxy" > /dev/null; then
    : # running
  elif [ -f /tmp/vnc-password.txt ]; then
    echo "⚠️  noVNC stopped! Restarting..."
    nohup websockify --web /opt/noVNC 6080 localhost:5900 \
      > /tmp/novnc.log 2>&1 &
    sleep 2
  fi

  # Cloudflare tunnel
  if pgrep -f "cloudflared" > /dev/null; then
    : # running
  elif [ -f /tmp/cloudflared.log ]; then
    echo "⚠️  Cloudflare tunnel died! Restarting..."
    nohup cloudflared tunnel --url http://localhost:6080 --no-autoupdate \
      > /tmp/cloudflared.log 2>&1 &
    sleep 3
    NEW_URL=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1 || true)
    if [ -n "$NEW_URL" ]; then
      echo "   ✅ New tunnel URL: $NEW_URL/vnc.html"
    fi
  fi

  # xRDP
  if pgrep -f "xrdp" > /dev/null; then
    : # running
  elif [ -f /tmp/rdp-password.txt ]; then
    echo "⚠️  xRDP stopped! Restarting..."
    sudo xrdp > /dev/null 2>&1 &
    sleep 2
  fi

  # Tailscale
  if pgrep -f "tailscaled" > /dev/null; then
    : # running
  elif [ -f /tmp/tailscale-state-save.tgz ]; then
    echo "⚠️  Tailscale stopped! Restarting..."
    nohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &
    sleep 3
  fi

  # Xvfb is always needed
  if ! pgrep -f "Xvfb" > /dev/null; then
    echo "⚠️  Xvfb stopped! Restarting..."
    RESOLUTION=$(cat /tmp/vps-resolution.txt 2>/dev/null || echo "1920x1080")
    sudo Xvfb :0 -screen 0 "${RESOLUTION}x24" -ac +extension GLX +render -noreset &>/dev/null &
    sleep 2
  fi

  # Light disk activity (prevent "idle" detection)
  echo "$(date -u '+%H:%M:%S') | Tick ${TICK} | ~${REMAINING} min left | Ext: ${EXTENSION_COUNT}" >> /tmp/vps-heartbeat.log

  # Progress bar every 5 minutes
  if [ $((TICK % 5)) -eq 0 ]; then
    TOTAL_DURATION=$(( (END_TIME) / 60 ))
    ELAPSED=$(( SECONDS / 60 ))
    if [ $TOTAL_DURATION -gt 0 ]; then
      FILLED=$(( ELAPSED * 20 / TOTAL_DURATION ))
    else
      FILLED=0
    fi
    [ $FILLED -gt 20 ] && FILLED=20
    EMPTY=$(( 20 - FILLED ))
    BAR=$(printf '#%.0s' $(seq 1 $FILLED 2>/dev/null) 2>/dev/null)$(printf '-%.0s' $(seq 1 $EMPTY 2>/dev/null) 2>/dev/null)
    echo "⏳  [${BAR}] ${REMAINING} min remaining (extended ${EXTENSION_COUNT}x)"
  fi

  sleep $INTERVAL
done
