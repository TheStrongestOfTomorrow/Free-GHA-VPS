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
  sudo apt-get install -y -qq x11vnc 2>/dev/null || {
    echo "❌ Failed to install x11vnc"
    exit 1
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
      exit 1
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
  echo "   ✅ websockify already available"
elif [ -f "$WEBSOCKIFY_PY" ]; then
  echo "   ✅ websockify available via noVNC"
else
  echo "   ⬇️  Installing websockify..."
  sudo pip3 install websockify numpy 2>/dev/null || {
    # Fallback: use noVNC's bundled websockify
    if [ ! -f "$WEBSOCKIFY_PY" ]; then
      cd "$NOVNC_DIR/utils"
      sudo git clone --depth 1 https://github.com/novnc/websockify.git 2>/dev/null || true
    fi
  }
  echo "   ✅ websockify ready"
fi

# ── Generate VNC password ──────────────────────────────────
VNC_PASS_FILE="$HOME/.vnc/passwd"
mkdir -p "$HOME/.vnc"

if [ ! -f "$VNC_PASS_FILE" ]; then
  VNC_PASS="${VNC_PASSWORD:-$(openssl rand -hex 6)}"
  # Use x11vnc's built-in password storage (creates proper binary format)
  x11vnc -storepasswd "$VNC_PASS" "$VNC_PASS_FILE" 2>/dev/null || {
    # Manual creation if x11vnc's -storepasswd fails
    echo "$VNC_PASS" | vncpasswd -f > "$VNC_PASS_FILE" 2>/dev/null || {
      # Last resort: use x11vnc again with explicit display
      mkdir -p "$HOME/.vnc"
      x11vnc -storepasswd "$VNC_PASS" "$VNC_PASS_FILE"
    }
  }
  # Save password for display (restrict permissions)
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
