#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Configure Chrome Remote Desktop
#  First run: uses auth code from start-host → instant connect
#  Returning: uses saved credentials → instant connect
# ============================================================
set -uo pipefail

PIN="${1:?❌ PIN is required. Pass it as the first argument.}"
MIN_PIN_LEN=6

# ── Validate PIN ─────────────────────────────────────────────
if [ ${#PIN} -lt $MIN_PIN_LEN ]; then
  echo "❌ PIN must be at least $MIN_PIN_LEN digits"
  exit 1
fi

# Validate PIN is numeric
if ! [[ "$PIN" =~ ^[0-9]+$ ]]; then
  echo "❌ PIN must be numeric (digits only)"
  exit 1
fi

CRD_DIR="$HOME/.config/google-chrome-remote-desktop"
mkdir -p "$CRD_DIR"

# ── Save PIN for reference ───────────────────────────────────
echo "🔑 Setting CRD PIN..."
echo "$PIN" > "$CRD_DIR/pin"
chmod 600 "$CRD_DIR/pin"

# ── Kill any existing CRD processes ──────────────────────────
sudo pkill -f chrome-remote-desktop 2>/dev/null || true
sleep 2

# ── Check if we have saved credentials (returning user) ─────
if [ -f "$CRD_DIR/Credentials" ] && [ -s "$CRD_DIR/Credentials" ]; then
  echo "✅ Found saved CRD credentials — skipping authorization!"
  echo "   Starting Chrome Remote Desktop..."

  # Kill stale CRD processes first
  sudo pkill -9 -f chrome-remote-desktop 2>/dev/null || true
  sleep 2

  # Start CRD daemon in background using the correct start-host method
  DISPLAY=:0 nohup /opt/google/chrome-remote-desktop/start-host \
    --pin="$PIN" \
    --name="Free-GHA-VPS" < /dev/null > /tmp/crd.log 2>&1 &
  sleep 5

  # Verify it's online
  for i in $(seq 1 30); do
    if pgrep -f "chrome-remote-desktop" > /dev/null; then
      echo ""
      echo "✅ Chrome Remote Desktop is ONLINE!"
      echo "   🔗 Connect: https://remotedesktop.google.com/access"
      echo "   🔑 PIN: ${PIN}"
      exit 0
    fi
    sleep 2
  done

  echo "⚠️  CRD starting... check remotedesktop.google.com/access in a moment"
  exit 0
fi

# ── First-time setup: No credentials yet ─────────────────────
echo "🆕 First-time setup — Chrome Remote Desktop needs authorization"
echo ""

# If start-host is available, try using it with the PIN
if [ -x /opt/google/chrome-remote-desktop/start-host ]; then
  echo "   Starting CRD host with PIN..."
  DISPLAY=:0 nohup /opt/google/chrome-remote-desktop/start-host \
    --pin="$PIN" \
    --name="Free-GHA-VPS" > /tmp/crd.log 2>&1 &
  CRD_PID=$!
  sleep 5
else
  # Fallback: start the CRD daemon directly
  nohup /opt/google/chrome-remote-desktop/chrome-remote-desktop --start > /tmp/crd.log 2>&1 &
  CRD_PID=$!
  sleep 5
fi

# Try to extract the auth URL from CRD logs
AUTH_URL=""
MAX_AUTH_WAIT=60

echo "🔍 Looking for authorization link..."
for i in $(seq 1 $MAX_AUTH_WAIT); do
  # CRD may output various URL patterns
  AUTH_URL=$(grep -oP 'https://remotedesktop\.google\.com[^ "'\''<>]*' /tmp/crd.log 2>/dev/null | head -1 || true)

  if [ -z "$AUTH_URL" ]; then
    AUTH_URL=$(grep -oP 'https://accounts\.google\.com/o/oauth2[^ "'\''<>]*' /tmp/crd.log 2>/dev/null | head -1 || true)
  fi

  if [ -z "$AUTH_URL" ]; then
    AUTH_URL=$(grep -oP 'https://[^ "'\''<>]*google[^ "'\''<>]*auth[^ "'\''<>]*' /tmp/crd.log 2>/dev/null | head -1 || true)
  fi

  if [ -n "$AUTH_URL" ]; then
    break
  fi

  # Check if CRD crashed
  if ! kill -0 $CRD_PID 2>/dev/null; then
    break
  fi

  echo -n "."
  sleep 1
done

echo ""

if [ -n "$AUTH_URL" ]; then
  # Display the auth URL prominently using GitHub Actions annotations
  echo "::notice::🔗 AUTHORIZE YOUR VPS: ${AUTH_URL}"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  🔗  CLICK THIS LINK TO AUTHORIZE YOUR VPS:"
  echo ""
  echo "  ${AUTH_URL}"
  echo ""
  echo "  ⏱️  You have 3 minutes to click it!"
  echo "  🔑  Your PIN: ${PIN}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
  # Fallback: guide user to the headless setup page
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  🔗  ONE-CLICK AUTHORIZATION NEEDED"
  echo ""
  echo "  Step 1: Open this link 👇"
  echo "  https://remotedesktop.google.com/headless"
  echo ""
  echo "  Step 2: Sign in with Google → Click 'Next'"
  echo "          → Choose 'Debian Linux' → Copy the command"
  echo ""
  echo "  Step 3: Just extract the --code value from the command"
  echo "          It looks like: 4/0AX4XfWh..."
  echo ""
  echo "  Step 4: Re-run this workflow with the code as input!"
  echo "  🔑  Your PIN: ${PIN}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "::notice::🔗 Visit https://remotedesktop.google.com/headless to authorize"
  echo "::notice::🔑 Your CRD PIN is: ${PIN}"
fi

# Wait for the user to authorize (credentials file will appear)
echo ""
echo "⏳ Waiting for you to authorize (checking every 5 seconds)..."
AUTH_WAIT=180  # 3 minutes to authorize

for i in $(seq 1 $((AUTH_WAIT / 5))); do
  if [ -f "$CRD_DIR/Credentials" ] && [ -s "$CRD_DIR/Credentials" ]; then
    echo ""
    echo "✅ Authorization detected! CRD is now linked to your Google account."
    echo "   🔗 Connect at: https://remotedesktop.google.com/access"
    echo "   🔑 PIN: ${PIN}"
    echo ""
    echo "   💡 Next time you run this, authorization will be instant!"
    exit 0
  fi
  echo -n "."
  sleep 5
done

echo ""
echo "⚠️  Authorization timed out. Don't worry — your VPS is still running!"
echo "   Try connecting at https://remotedesktop.google.com/access anyway."
echo "   If it doesn't work, re-run the workflow and authorize faster."
