#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - rclone Setup Helper
#  Run this LOCALLY to generate your RCLONE_CONFIG secret
#
#  Usage:
#    bash rclone-setup.sh
#
#  Then copy the base64 output to your GitHub secret
# ============================================================
set -euo pipefail

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ☁️  Google Drive Setup for Free GHA VPS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  This will link your Google Drive for 15GB storage."
echo "  Your data will be backed up automatically."
echo ""

# Check if rclone is installed
if ! command -v rclone &>/dev/null; then
  echo "📦 Installing rclone..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    brew install rclone 2>/dev/null || {
      echo "❌ Install rclone first: brew install rclone"
      exit 1
    }
  else
    curl -s https://rclone.org/install.sh | sudo bash 2>/dev/null || {
      echo "❌ Install rclone first: curl https://rclone.org/install.sh | sudo bash"
      exit 1
    }
  fi
fi

echo "✅ rclone found: $(rclone version | head -1)"
echo ""

# Configure Google Drive remote
echo "🔗 Configuring Google Drive..."
echo "   Follow the prompts (choose defaults if unsure):"
echo ""
echo "   - Name:       gdrive"
echo "   - Storage:    Google Drive"
echo "   - Scope:      Full access"
echo "   - Client ID:  leave blank (default)"
echo "   - Client secret: leave blank (default)"
echo ""

rclone config create gdrive drive scope=drive 2>&1 || {
  echo ""
  echo "⚠️  Interactive config failed. Try running: rclone config"
  echo "   Then create a remote called 'gdrive' with Google Drive storage."
  echo ""
  exit 1
}

echo ""
echo "✅ Google Drive configured!"
echo ""

# Show the config file location
CONFIG_FILE="$HOME/.config/rclone/rclone.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/rclone/rclone.conf"
fi

if [ -f "$CONFIG_FILE" ]; then
  # Base64 encode it
  CONFIG_B64=$(base64 -w 0 "$CONFIG_FILE")

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  🔑 YOUR RCLONE_CONFIG SECRET"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  Copy this ENTIRE line:"
  echo ""
  echo "  $CONFIG_B64"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  📋 Next steps:"
  echo ""
  echo "  1. Go to your repo Settings → Secrets → Actions"
  echo "  2. Click 'New repository secret'"
  echo "  3. Name: RCLONE_CONFIG"
  echo "  4. Value: Paste the line above"
  echo "  5. In the VPS workflow, set 'storage' to 'drive' or 'auto'"
  echo ""
  echo "  💾 You now have 15GB of persistent storage!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
  echo "❌ Config file not found at $CONFIG_FILE"
  echo "   Run 'rclone config' to create it manually"
fi
