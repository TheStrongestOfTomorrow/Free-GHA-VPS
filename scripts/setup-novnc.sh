#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Setup noVNC
#  Installs VNC server, noVNC web client, websockify
# ============================================================
set -euo pipefail

CACHE_DIR="/tmp/vps-cache"
NOVNC_DIR="/opt/noVNC"
WEBSOCKIFY_PY="/opt/noVNC/utils/websockify"

echo "🖥️  Setting up noVNC..."

# ── Install x11vnc (VNC server for the X11 display) ─────────
if ! command -v x11vnc &>/dev/null; then
  echo "   ⬇️  Installing x11vnc..."
  sudo apt-get install -y -qq x11vnc 2>/dev/null || {
    echo "❌ Failed to install x11vnc"
    kill -INT $$
  }
  echo "   ✅ x11vnc installed"
else
  echo "   ✅ x11vnc already available"
fi

# ── Install noVNC (web-based VNC client) ────────────────────
if [ -d "$NOVNC_DIR" ] && [ -f "$NOVNC_DIR/vnc.html" ]; then
  echo "   ✅ noVNC already installed"
else
  # Try to use cached copy first
  if [ -f "$CACHE_DIR/noVNC.tar.gz" ]; then
    echo "   ✅ Restoring noVNC from cache..."
    sudo mkdir -p "$NOVNC_DIR"
    sudo tar -xzf "$CACHE_DIR/noVNC.tar.gz" -C /opt/ 2>/dev/null || {
      rm -rf "$NOVNC_DIR"
      # Fall through to download
      CACHE_DIR="" # force download
    }
  fi

  if [ ! -d "$NOVNC_DIR" ] || [ ! -f "$NOVNC_DIR/vnc.html" ]; then
    echo "   ⬇️  Downloading noVNC..."
    sudo mkdir -p /opt
    cd /opt
    sudo git clone --depth 1 https://github.com/novnc/noVNC.git 2>/dev/null || {
      echo "❌ Failed to clone noVNC"
      kill -INT $$
    }
    # Cache the download
    if [ -n "${CACHE_DIR:-}" ]; then
      sudo tar -czf "$CACHE_DIR/noVNC.tar.gz" -C /opt noVNC 2>/dev/null || true
    fi
    echo "   ✅ noVNC installed"
  fi
fi

# ── Install websockify (WebSocket proxy) ────────────────────
if command -v websockify &>/dev/null; then
  echo "   ✅ websockify already available (system)"
elif [ -f "$WEBSOCKIFY_PY" ]; then
  echo "   ✅ websockify available via noVNC"
else
  echo "   ⬇️  Installing websockify..."
  sudo apt-get install -y -qq python3-websockify python3-numpy 2>/dev/null || {
    sudo pip3 install --quiet websockify numpy 2>/dev/null || true
  }
  if [ ! -f "$WEBSOCKIFY_PY" ] && ! command -v websockify &>/dev/null; then
    cd "$NOVNC_DIR/utils"
    sudo git clone --depth 1 https://github.com/novnc/websockify.git 2>/dev/null || true
  fi
  echo "   ✅ websockify ready"
fi

# ── Generate VNC password ──────────────────────────────────
VNC_PASS_FILE="$HOME/.vnc/passwd"
mkdir -p "$HOME/.vnc"

if [ ! -f "$VNC_PASS_FILE" ]; then
  VNC_PASS="${VNC_PASSWORD:-$(openssl rand -hex 6)}"
  x11vnc -storepasswd "$VNC_PASS" "$VNC_PASS_FILE" 2>/dev/null || {
    if command -v vncpasswd &>/dev/null; then
      echo "$VNC_PASS" | vncpasswd -f > "$VNC_PASS_FILE" 2>/dev/null
    else
      x11vnc -storepasswd "$VNC_PASS" "$VNC_PASS_FILE"
    fi
  }
  echo "$VNC_PASS" > /tmp/vnc-password.txt
  chmod 600 "$VNC_PASS_FILE" /tmp/vnc-password.txt
  echo "   🔑 VNC password generated"
else
  echo "   🔑 VNC password file exists"
fi

echo ""
echo "✅ noVNC setup complete!"
echo "   VNC Server: x11vnc"
echo "   Web Client: noVNC at $NOVNC_DIR"
echo "   Password:   $(cat /tmp/vnc-password.txt 2>/dev/null || echo 'set')"
