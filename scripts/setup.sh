#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Setup Script (Cache-Aware)
#  First run:  downloads & installs everything (~2.5 min)
#  Cached run: skips downloads, just installs from cache (~15s)
# ============================================================
set -euo pipefail

CACHE_DIR="/tmp/vps-cache"
PACKAGES_DIR="$CACHE_DIR/packages"
DEBS_DIR="$CACHE_DIR/debs"
APT_CACHE="$CACHE_DIR/apt-cache"

# ── Track what gets downloaded ───────────────────────────────
mkdir -p "$PACKAGES_DIR" "$DEBS_DIR" "$APT_CACHE"

# ── Speed up apt ──────────────────────────────────────────────
sudo sed -i 's|^deb http://archive|deb mirror://mirrors.ubuntu.com/mirrors.txt|g' /etc/apt/sources.list 2>/dev/null || true

# Copy cached apt packages back to apt cache
if [ "$(ls -A "$APT_CACHE" 2>/dev/null)" ]; then
  echo "📦 Restoring apt cache..."
  sudo cp "$APT_CACHE"/*.deb /var/cache/apt/archives/ 2>/dev/null || true
fi

sudo apt-get update -qq 2>/dev/null

# ── Helper: install from cache if available, else download ───
install_or_cache() {
  local NAME="$1"
  shift
  if [ "$(ls -A "$DEBS_DIR" 2>/dev/null)" ]; then
    echo "📦 Installing $NAME (from cache)..."
  else
    echo "📦 Installing $NAME..."
  fi
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" 2>/dev/null || true
}

# ── Install virtual display ───────────────────────────────────
install_or_cache "Xvfb" xvfb

# ── Install lightweight desktop environment (XFCE4) ──────────
install_or_cache "XFCE4" \
  xfce4 xfce4-terminal xfce4-whiskermenu-plugin \
  xfce4-panel xfce4-settings dbus-x11 at-spi2-core

# ── Install Google Chrome ────────────────────────────────────
echo "📦 Installing Google Chrome..."
if [ -f "$DEBS_DIR/google-chrome-stable.deb" ]; then
  echo "   ✅ Using cached Chrome deb"
  sudo apt-get install -y -qq "$DEBS_DIR/google-chrome-stable.deb" > /dev/null 2>&1
else
  if ! command -v google-chrome-stable &>/dev/null; then
    wget -q -O "$DEBS_DIR/google-chrome-stable.deb" \
      https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    sudo apt-get install -y -qq "$DEBS_DIR/google-chrome-stable.deb" > /dev/null 2>&1
  fi
fi

# ── Install Chrome Remote Desktop ────────────────────────────
echo "📦 Installing Chrome Remote Desktop..."
if [ -f "$DEBS_DIR/chrome-remote-desktop.deb" ]; then
  echo "   ✅ Using cached CRD deb"
  sudo apt-get install -y -qq "$DEBS_DIR/chrome-remote-desktop.deb" > /dev/null 2>&1
else
  if ! command -v chrome-remote-desktop &>/dev/null; then
    wget -q -O "$DEBS_DIR/chrome-remote-desktop.deb" \
      https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
    sudo apt-get install -y -qq "$DEBS_DIR/chrome-remote-desktop.deb" > /dev/null 2>&1
  fi
fi

# ── Install essential utilities ──────────────────────────────
install_or_cache "utilities" \
  curl wget git nano htop neofetch python3 python3-pip \
  jq net-tools unzip expect zstd

# ── Install connection packages (noVNC, xRDP, etc.) ────────
echo "📦 Installing remote desktop packages..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  x11vnc \
  xrdp \
  ssh \
  openssl \
  xxd \
  > /dev/null 2>&1

# ── Install Python packages for noVNC ──────────────────────
echo "📦 Installing Python packages for noVNC..."
sudo pip3 install --quiet websockify numpy 2>/dev/null || true

# ── Download cloudflared (tunnel binary) ────────────────────
echo "📦 Downloading cloudflared..."
if [ -f "$DEBS_DIR/cloudflared" ]; then
  echo "   ✅ Using cached cloudflared"
  sudo cp "$DEBS_DIR/cloudflared" /usr/local/bin/cloudflared
  sudo chmod +x /usr/local/bin/cloudflared
else
  if ! command -v cloudflared &>/dev/null; then
    wget -q -O "$DEBS_DIR/cloudflared" \
      https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
    sudo cp "$DEBS_DIR/cloudflared" /usr/local/bin/cloudflared
    sudo chmod +x /usr/local/bin/cloudflared
  fi
fi

# ── Clone noVNC web client ─────────────────────────────────
echo "📦 Setting up noVNC web client..."
NOVNC_DIR="/opt/noVNC"
if [ ! -d "$NOVNC_DIR" ] || [ ! -f "$NOVNC_DIR/vnc.html" ]; then
  if [ -f "$PACKAGES_DIR/noVNC.tar.gz" ]; then
    echo "   ✅ Using cached noVNC"
    sudo mkdir -p /opt
    sudo tar -xzf "$PACKAGES_DIR/noVNC.tar.gz" -C /opt/ 2>/dev/null || true
  fi
  if [ ! -d "$NOVNC_DIR" ] || [ ! -f "$NOVNC_DIR/vnc.html" ]; then
    sudo mkdir -p /opt
    cd /opt
    sudo git clone --depth 1 https://github.com/novnc/noVNC.git 2>/dev/null || true
  fi
fi
# Cache it
if [ -d "$NOVNC_DIR" ] && [ ! -f "$PACKAGES_DIR/noVNC.tar.gz" ]; then
  sudo tar -czf "$PACKAGES_DIR/noVNC.tar.gz" -C /opt noVNC 2>/dev/null || true
fi

# ── Download Tailscale ─────────────────────────────────────
echo "📦 Downloading Tailscale..."
if ! command -v tailscale &>/dev/null; then
  if [ -f "$DEBS_DIR/tailscale_latest.tgz" ]; then
    echo "   ✅ Using cached Tailscale"
    sudo tar -xzf "$DEBS_DIR/tailscale_latest.tgz" -C /
  else
    wget -q -O "$DEBS_DIR/tailscale_latest.tgz" \
      https://pkgs.tailscale.com/stable/tailscale_latest_amd64.tgz
    sudo tar -xzf "$DEBS_DIR/tailscale_latest.tgz" -C /
  fi
fi

# ── Save apt cache for next run ──────────────────────────────
echo "💾 Saving apt cache..."
cp /var/cache/apt/archives/*.deb "$APT_CACHE/" 2>/dev/null || true

# ── Prevent Chrome auto-restart and crash reporting ──────────
echo "⚙️  Configuring Chrome..."
sudo mkdir -p /etc/chromium-browser/policies/managed
echo '{ "AutoUpdateCheckPeriodMinutes": 0, "CloudReportingEnabled": false }' \
  | sudo tee /etc/chromium-browser/policies/managed/crd.json > /dev/null

# ── Configure CRD to use existing desktop (no new session) ──
echo "⚙️  Configuring CRD daemon settings..."
sudo sed -i 's/^Enabled=true$/Enabled=false/' /etc/default/chrome-remote-desktop 2>/dev/null || true
sudo mkdir -p /etc/chrome-remote-desktop
echo '{"hosted_apps":[],"ipv6_enabled":false,"remoting":{"use_voice_input":false,"use_video_input":false,"audio_capture_enabled":false}}' \
  | sudo tee /etc/chrome-remote-desktop/default.json > /dev/null

# ── Set up runner home directory ─────────────────────────────
mkdir -p "$HOME/Desktop" "$HOME/Documents" "$HOME/Downloads"
echo "xfce4-session" > "$HOME/.xsession"

# ── Finished ─────────────────────────────────────────────────
# Write a cache marker with the current cache size
CACHE_SIZE=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
echo "$CACHE_SIZE" > "$CACHE_DIR/.cache-size"

echo ""
echo "✅ VPS environment setup complete!"
echo "   Desktop:  XFCE4"
echo "   Chrome:   $(google-chrome-stable --version 2>/dev/null || echo 'installed')"
echo "   CRD:      $(chrome-remote-desktop --version 2>/dev/null || echo 'installed')"
echo "   Cache:    $CACHE_SIZE"
