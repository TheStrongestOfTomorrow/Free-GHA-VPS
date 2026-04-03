#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Setup xRDP
#  Installs and configures xRDP for real RDP connections
# ============================================================
set -euo pipefail

echo "🖥️  Setting up xRDP..."

# ── Install xRDP ───────────────────────────────────────────
if command -v xrdp &>/dev/null; then
  echo "   ✅ xRDP already installed"
else
  sudo apt-get install -y -qq xrdp 2>/dev/null || {
    echo "❌ Failed to install xRDP"
    exit 1
  }
  echo "   ✅ xRDP installed"
fi

# ── Configure xRDP to connect to existing Xvfb display :0 ──
echo "   ⚙️  Configuring xRDP..."

# Create xRDP config to use the existing display
XRDP_INI="/etc/xrdp/xrdp.ini"

if [ -f "$XRDP_INI" ]; then
  # Set max connections
  sudo sed -i 's/max_bpp=32/max_bpp=32/' "$XRDP_INI"
  sudo sed -i 's/port=3389/port=3389/' "$XRDP_INI"

  # Set security layer to negotiate (more compatible)
  sudo sed -i 's/security_layer=negotiate/security_layer=negotiate/' "$XRDP_INI" 2>/dev/null || true
  sudo sed -i 's/security_layer=rdp/security_layer=negotiate/' "$XRDP_INI" 2>/dev/null || true
  sudo sed -i 's/security_layer=tls/security_layer=negotiate/' "$XRDP_INI" 2>/dev/null || true

  # Allow any encryption
  sudo sed -i 's/crypt_level=high/crypt_level=low/' "$XRDP_INI" 2>/dev/null || true
  sudo sed -i 's/crypt_level=medium/crypt_level=low/' "$XRDP_INI" 2>/dev/null || true
fi

# ── Set up the runner as xRDP user ─────────────────────────
# Configure xRDP to allow password-less or runner access
echo "runner" | sudo xauth add "$DISPLAY" . "$(xxd -l 16 -p /dev/urandom)" 2>/dev/null || true

# Set a password for the runner user (needed for RDP auth)
RDP_PASS="${RDP_PASSWORD:-$(openssl rand -base64 12)}"
echo "runner:$RDP_PASS" | sudo chpasswd 2>/dev/null || true
echo "$RDP_PASS" > /tmp/rdp-password.txt

# Configure session to connect to the existing display
XRDP_STARTWM="/etc/xrdp/startwm.sh"
if [ -f "$XRDP_STARTWM" ]; then
  sudo cp "$XRDP_STARTWM" "${XRDP_STARTWM}.bak"
  sudo tee "$XRDP_STARTWM" > /dev/null <<'XEOF'
#!/bin/sh
# Connect to the existing XFCE session on display :0
export DISPLAY=:0
exec /bin/bash
XEOF
  sudo chmod +x "$XRDP_STARTWM"
fi

# ── Start xRDP service ─────────────────────────────────────
echo "   🚀 Starting xRDP..."

# Stop any existing xrdp
sudo systemctl stop xrdp 2>/dev/null || sudo pkill -f xrdp 2>/dev/null || true
sleep 1

# Start xrdp
sudo xrdp 2>/dev/null || sudo /usr/sbin/xrdp 2>/dev/null || {
  echo "   ⚠️  xRDP may need manual start"
}

sleep 2

# Verify xRDP is running
if pgrep -f "xrdp" > /dev/null; then
  echo "   ✅ xRDP running on port 3389"
else
  echo "   ⚠️  xRDP process not detected — will use Tailscale for access"
fi

# Save password for display
echo "RDP_PASS=$RDP_PASS" >> $GITHUB_ENV

echo ""
echo "✅ xRDP setup complete!"
echo "   Port: 3389"
echo "   Username: runner"
echo "   Password: $RDP_PASS"
echo ""
echo "   ⚠️  RDP port is NOT publicly accessible on GitHub runners."
echo "   Use Tailscale to connect securely."
