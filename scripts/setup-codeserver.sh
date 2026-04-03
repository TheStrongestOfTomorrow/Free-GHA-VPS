#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Setup Code-Server (Browser VS Code)
#  Lightweight coding environment — no desktop needed
#  First run: ~45 sec, cached: ~10 sec
# ============================================================
set -euo pipefail

CACHE_DIR="/tmp/cs-cache"
DEBS_DIR="$CACHE_DIR/debs"

mkdir -p "$DEBS_DIR"

echo "💻 Setting up code-server..."

# ── Speed up apt ──────────────────────────────────────────────
sudo sed -i 's|^deb http://archive|deb mirror://mirrors.ubuntu.com/mirrors.txt|g' /etc/apt/sources.list 2>/dev/null || true
sudo apt-get update -qq 2>/dev/null

# ── Install essential tools ───────────────────────────────────
echo "📦 Installing base tools..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  curl wget git nano htop neofetch python3 python3-pip \
  jq net-tools unzip zstd build-essential \
  > /dev/null 2>&1

# ── Install code-server ──────────────────────────────────────
echo "📦 Installing code-server..."
if [ -f "$DEBS_DIR/code-server.deb" ]; then
  echo "   ✅ Using cached code-server deb"
  sudo dpkg -i "$DEBS_DIR/code-server.deb" > /dev/null 2>&1 || \
    sudo apt-get install -y -qq -f > /dev/null 2>&1
else
  # Install from official script
  curl -fsSL https://code-server.dev/install.sh | sh 2>/dev/null || {
    # Fallback: download .deb directly
    CS_VERSION="4.96.4"
    wget -q -O "$DEBS_DIR/code-server.deb" \
      "https://github.com/coder/code-server/releases/download/v${CS_VERSION}/code-server_${CS_VERSION}_amd64.deb"
    sudo dpkg -i "$DEBS_DIR/code-server.deb" > /dev/null 2>&1 || \
      sudo apt-get install -y -qq -f > /dev/null 2>&1
  }
  # Cache the deb for next time
  if command -v dpkg &>/dev/null; then
    dpkg -L code-server 2>/dev/null | head -1 > /dev/null && {
      # Find the installed deb in apt cache
      cp /var/cache/apt/archives/code-server*.deb "$DEBS_DIR/" 2>/dev/null || true
    }
  fi
fi

# ── Download cloudflared (for tunneling) ─────────────────────
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

# ── Install common dev tools (Node.js, Python extras) ───────
echo "📦 Installing dev tools..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  nodejs npm \
  openssh-client \
  > /dev/null 2>&1 || true

# ── Set up workspace directory ───────────────────────────────
mkdir -p /home/runner/workspace
sudo chown -R runner:runner /home/runner/workspace

# ── Configure code-server ────────────────────────────────────
mkdir -p /home/runner/.config/code-server

echo "✅ Code-server setup complete!"
echo "   Version: $(code-server --version 2>/dev/null || echo 'installed')"
