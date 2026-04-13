#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Notification System
#  Sends alerts via Discord Webhook + Telegram Bot API
#  Zero dependencies — pure curl, open-source/native APIs
#
#  Usage:
#    bash scripts/notify.sh "event" "title" "message" "color"
#
#  Events: start | ready | error | end | save | extend
#  Colors (decimal): green=3066993 | blue=3447003 | red=15158332
#                    orange=15105570 | purple=10181040
# ============================================================
set -euo pipefail

EVENT="${1:-info}"
TITLE="${2:-Notification}"
MESSAGE="${3:-No details provided}"
COLOR="${4:-3447003}"
REPO="${GITHUB_REPOSITORY:-Free-GHA-VPS}"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${REPO}/actions/runs/${GITHUB_RUN_ID:-0}"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# ═══════════════════════════════════════════════════════════════
#  DISCORD WEBHOOK (zero-dependency, just curl)
# ═══════════════════════════════════════════════════════════════
DISCORD_URL="${DISCORD_WEBHOOK_URL:-}"

if [ -n "$DISCORD_URL" ]; then
  # Pick emoji based on event
  EMOJI="📢"
  case "$EVENT" in
    start)  EMOJI="🚀" ;;
    ready)  EMOJI="✅" ;;
    error)  EMOJI="❌" ;;
    end)    EMOJI="👋" ;;
    save)   EMOJI="💾" ;;
    extend) EMOJI="⏰" ;;
    stop)   EMOJI="🛑" ;;
    info)   EMOJI="📢" ;;
  esac

  # Build the embed JSON
  # Escape quotes and newlines in message for JSON safety
  SAFE_TITLE=$(echo "$TITLE" | sed 's/"/\\"/g')
  SAFE_MESSAGE=$(echo "$MESSAGE" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

  DISCORD_PAYLOAD=$(cat <<DISCORD_EOF
{
  "username": "Free GHA VPS Bot",
  "avatar_url": "https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png",
  "embeds": [
    {
      "title": "${EMOJI} ${SAFE_TITLE}",
      "description": "${SAFE_MESSAGE}",
      "color": ${COLOR},
      "url": "${RUN_URL}",
      "timestamp": "${TIMESTAMP}",
      "footer": {
        "text": "${REPO}"
      },
      "fields": [
        {
          "name": "Event",
          "value": "${EVENT}",
          "inline": true
        },
        {
          "name": "Run #${GITHUB_RUN_ID:-?}",
          "value": "[View Logs](${RUN_URL})",
          "inline": true
        }
      ]
    }
  ]
}
DISCORD_EOF
  )

  curl -sf -X POST "$DISCORD_URL" \
    -H "Content-Type: application/json" \
    -d "$DISCORD_PAYLOAD" > /dev/null 2>&1 && \
    echo "📨 Discord notification sent (${EVENT})" || \
    echo "⚠️  Discord notification failed (${EVENT})"
else
  echo "ℹ️  No DISCORD_WEBHOOK_URL configured — skipping Discord"
fi

# ═══════════════════════════════════════════════════════════════
#  TELEGRAM BOT API (zero-dependency, just curl)
# ═══════════════════════════════════════════════════════════════
TELEGRAM_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT="${TELEGRAM_CHAT_ID:-}"

if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT" ]; then
  # Pick emoji
  EMOJI="📢"
  case "$EVENT" in
    start)  EMOJI="🚀" ;;
    ready)  EMOJI="✅" ;;
    error)  EMOJI="❌" ;;
    end)    EMOJI="👋" ;;
    save)   EMOJI="💾" ;;
    extend) EMOJI="⏰" ;;
    stop)   EMOJI="🛑" ;;
    info)   EMOJI="📢" ;;
  esac

  # Escape markdown special chars in message (Telegram MarkdownV2 requires escaping 18 chars)
  SAFE_MSG=$(echo "$MESSAGE" | sed 's/[_*`\[\]()~>#+\-=|{}.!]/\\&/g')
  SAFE_TITLE_TG=$(echo "$TITLE" | sed 's/[_*`\[\]()~>#+\-=|{}.!]/\\&/g')

  TELEGRAM_PAYLOAD=$(cat <<TELEGRAM_EOF
{
  "chat_id": "${TELEGRAM_CHAT}",
  "text": "${EMOJI} *${SAFE_TITLE_TG}*\n\n${SAFE_MSG}\n\n🔗 [View Run](${RUN_URL})\n📦 ${REPO}",
  "parse_mode": "MarkdownV2",
  "disable_web_page_preview": false
}
TELEGRAM_EOF
  )

  curl -sf -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$TELEGRAM_PAYLOAD" > /dev/null 2>&1 && \
    echo "📨 Telegram notification sent (${EVENT})" || \
    echo "⚠️  Telegram notification failed (${EVENT})"
else
  echo "ℹ️  No TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID configured — skipping Telegram"
fi

# ═══════════════════════════════════════════════════════════════
#  Summary
# ═══════════════════════════════════════════════════════════════
SENT=0
[ -n "$DISCORD_URL" ] && SENT=$((SENT + 1))
[ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT" ] && SENT=$((SENT + 1))

if [ $SENT -eq 0 ]; then
  echo "ℹ️  No notifications configured. Add secrets to enable:"
  echo "   - DISCORD_WEBHOOK_URL  (for Discord)"
  echo "   - TELEGRAM_BOT_TOKEN   (for Telegram bot)"
  echo "   - TELEGRAM_CHAT_ID     (for Telegram chat)"
fi
