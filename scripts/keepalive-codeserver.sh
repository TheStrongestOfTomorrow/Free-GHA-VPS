#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Code-Server Keepalive
#  Lightweight timer — keeps code-server + tunnel alive
#  Supports session extension via signal branches
# ============================================================
set -euo pipefail

DURATION="${1:-30}"
ACTIVE_MINUTES=$((DURATION - 2))
END_TIME=$((SECONDS + (ACTIVE_MINUTES * 60)))
EXTENSION_COUNT=0
MAX_EXTENSIONS=5

echo "🔄 Code-Server keepalive started — ${ACTIVE_MINUTES} minutes"
echo "   Ends at: $(date -d "+${ACTIVE_MINUTES} minutes" '+%H:%M:%S UTC')"
echo ""

INTERVAL=60
TICK=0
LAST_CHECKED_BRANCHES=""

check_for_extension() {
  SIGNAL_BRANCHES=$(git ls-remote --heads origin 'refs/heads/vps-extend-*' 2>/dev/null || true)

  if [ -z "$SIGNAL_BRANCHES" ]; then
    return 1
  fi

  if [ "$SIGNAL_BRANCHES" = "$LAST_CHECKED_BRANCHES" ]; then
    return 1
  fi

  SIGNAL_BRANCH=$(echo "$SIGNAL_BRANCHES" | head -1 | awk '{print $2}' | sed 's|refs/heads/||')
  EXTRA_MINUTES=30
  SIGNAL_DATA=$(git fetch origin "$SIGNAL_BRANCH" 2>/dev/null && git show "origin/$SIGNAL_BRANCH:.vps-extend-signal" 2>/dev/null || true)
  if [ -n "$SIGNAL_DATA" ]; then
    EXTRA_MINUTES=$(echo "$SIGNAL_DATA" | cut -d'|' -f2)
    EXTRA_MINUTES="${EXTRA_MINUTES:-30}"
  fi

  if [ "$EXTRA_MINUTES" -gt 30 ]; then
    EXTRA_MINUTES=30
  fi

  if [ $EXTENSION_COUNT -ge $MAX_EXTENSIONS ]; then
    echo "⚠️  Maximum extensions ($MAX_EXTENSIONS) reached."
    LAST_CHECKED_BRANCHES="$SIGNAL_BRANCHES"
    return 1
  fi

  git push origin --delete "$SIGNAL_BRANCH" 2>/dev/null || true
  LAST_CHECKED_BRANCHES=""

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
  if [ $SECONDS -ge $END_TIME ]; then
    echo "✅ Keepalive completed. Session done."
    exit 0
  fi

  TICK=$((TICK + 1))
  REMAINING=$(( (END_TIME - SECONDS) / 60 ))

  # Check for extensions every 3 min
  if [ $((TICK % 3)) -eq 0 ]; then
    check_for_extension || true
    REMAINING=$(( (END_TIME - SECONDS) / 60 ))
    if [ $REMAINING -lt 1 ]; then
      echo "✅ Keepalive completed. Session done."
      exit 0
    fi
  fi

  # ── Auto-restart code-server if crashed ─────────────────────
  if ! pgrep -f "code-server" > /dev/null; then
    echo "⚠️  Code-server stopped! Restarting..."
    PASS=$(cat /tmp/cs-password.txt 2>/dev/null || echo "code-server")
    cat > /home/runner/.config/code-server/config.yaml <<CONFIG_EOF
bind-addr: 0.0.0.0:8080
auth: password
password: ${PASS}
cert: false
CONFIG_EOF
    nohup code-server --config /home/runner/.config/code-server/config.yaml \
      > /tmp/code-server.log 2>&1 &
    sleep 3
  fi

  # ── Auto-restart Cloudflare tunnel ──────────────────────────
  if ! pgrep -f "cloudflared" > /dev/null; then
    if [ -f /tmp/cloudflared.log ]; then
      echo "⚠️  Cloudflare tunnel died! Restarting..."
      nohup cloudflared tunnel --url http://localhost:8080 --no-autoupdate \
        > /tmp/cloudflared.log 2>&1 &
      sleep 3
      NEW_URL=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1 || true)
      if [ -n "$NEW_URL" ]; then
        echo "   ✅ New tunnel URL: $NEW_URL/"
      fi
    fi
  fi

  # ── Auto-restart localhost.run tunnel ───────────────────────
  if ! pgrep -f "localhost.run" > /dev/null && ! pgrep -f "ssh -R 80" > /dev/null; then
    if [ -f /tmp/cloudflared.log ]; then
      : # Cloudflare is primary, skip
    elif [ -f /tmp/ssh-tunnel.log ]; then
      echo "⚠️  localhost.run tunnel died! Restarting..."
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -R 80:localhost:8080 \
        -o ServerAliveInterval=60 \
        nokey@localhost.run > /tmp/ssh-tunnel.log 2>&1 &
      sleep 3
    fi
  fi

  # Heartbeat
  echo "$(date -u '+%H:%M:%S') | Tick ${TICK} | ~${REMAINING} min left | Ext: ${EXTENSION_COUNT}" >> /tmp/cs-heartbeat.log

  # Progress bar every 5 min
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
