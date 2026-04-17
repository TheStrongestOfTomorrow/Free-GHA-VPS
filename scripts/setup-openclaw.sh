#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Setup OpenClaw Environment
#  Installs Ollama, pulls ANY model (Ollama custom or Gemma),
#  and sets up the web chat UI with full model support
#  First run: ~3-5 min (model download), cached: ~30 sec
# ============================================================
set -euo pipefail

MODEL="${1:-gemma3:1b}"
MODEL_SOURCE="${2:-gemma}"
CACHE_DIR="/tmp/oc-cache"
DEBS_DIR="$CACHE_DIR/debs"

mkdir -p "$DEBS_DIR"

echo "🦞 Setting up OpenClaw environment..."
echo "   Model source: $MODEL_SOURCE"
echo "   Model: $MODEL"

# ── Speed up apt ──────────────────────────────────────────────
sudo sed -i 's|^deb http://archive|deb mirror://mirrors.ubuntu.com/mirrors.txt|g' /etc/apt/sources.list 2>/dev/null || true
sudo apt-get update -qq 2>/dev/null

# ── Install essential tools ───────────────────────────────────
echo "📦 Installing base tools..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  curl wget git nano htop jq net-tools unzip zstd python3 python3-pip \
  > /dev/null 2>&1

# ── Install Ollama ───────────────────────────────────────────
echo "📦 Installing Ollama..."
if [ -f "$DEBS_DIR/ollama" ]; then
  echo "   ✅ Using cached Ollama binary"
  sudo cp "$DEBS_DIR/ollama" /usr/local/bin/ollama
  sudo chmod +x /usr/local/bin/ollama
elif command -v ollama &>/dev/null; then
  echo "   ✅ Ollama already installed"
else
  curl -fsSL https://ollama.com/install.sh | sh 2>/dev/null || {
    echo "   ⬇️  Downloading Ollama binary..."
    sudo curl -sL -o /usr/local/bin/ollama \
      https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64
    sudo chmod +x /usr/local/bin/ollama
  }
  # Cache for next run
  if [ -f /usr/local/bin/ollama ]; then
    cp /usr/local/bin/ollama "$DEBS_DIR/ollama" 2>/dev/null || true
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

# ── Install Python dependencies for chat UI ──────────────────
echo "📦 Installing Python web dependencies..."
pip3 install --quiet aiohttp 2>/dev/null || true

# ── Create swap space to prevent OOM kills ──────────────────────
echo "💾 Setting up swap space to prevent OOM kills..."
if [ ! -f /swapfile ] || ! sudo swapon --show | grep -q swapfile; then
  sudo swapoff /swapfile 2>/dev/null || true
  sudo rm -f /swapfile 2>/dev/null || true
  sudo fallocate -l 4G /swapfile 2>/dev/null || \
    sudo dd if=/dev/zero of=/swapfile bs=1M count=4096 status=progress 2>/dev/null
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile 2>/dev/null
  sudo swapon /swapfile 2>/dev/null
  echo "   ✅ 4GB swap file created and activated"
else
  echo "   ✅ Swap file already active"
fi
free -h 2>/dev/null || true

# ── Free up memory ──────────────────────────────────────────────
echo "🧹 Freeing up memory by stopping unnecessary services..."
sudo systemctl stop mongod 2>/dev/null || true
sudo systemctl stop mysql 2>/dev/null || true
sudo systemctl stop postgresql 2>/dev/null || true
sudo systemctl stop apache2 2>/dev/null || true
sudo systemctl stop nginx 2>/dev/null || true
sudo systemctl stop snapd 2>/dev/null || true
sleep 1

# ── Start Ollama server (needed for model pull) ──────────────
echo "🚀 Starting Ollama server for model pull..."

# Kill any existing Ollama processes and free port 11434
sudo pkill -9 -f ollama 2>/dev/null || true
pkill -9 -f ollama 2>/dev/null || true
sleep 2

# Ensure port 11434 is free - kill anything still holding it
PORT_PID=$(sudo lsof -ti:11434 2>/dev/null || true)
if [ -n "$PORT_PID" ]; then
  echo "   🔓 Killing process $PORT_PID on port 11434..."
  sudo kill -9 $PORT_PID 2>/dev/null || true
  sleep 1
fi

# Set up Ollama data directory
sudo mkdir -p /home/runner/.ollama
sudo chown -R runner:runner /home/runner/.ollama

# Start Ollama in background
export OLLAMA_HOST="0.0.0.0:11434"
export OLLAMA_MODELS="/home/runner/.ollama/models"
nohup ollama serve > /tmp/ollama.log 2>&1 &
OLLAMA_PID=$!
sleep 5

# Verify Ollama is running
if ! kill -0 $OLLAMA_PID 2>/dev/null; then
  echo "⚠️  Ollama server failed to start on port 11434, trying alternate port..."
  cat /tmp/ollama.log
  # Try alternate port 11436
  export OLLAMA_HOST="0.0.0.0:11436"
  nohup ollama serve > /tmp/ollama.log 2>&1 &
  OLLAMA_PID=$!
  sleep 5
  if ! kill -0 $OLLAMA_PID 2>/dev/null; then
    echo "❌ Ollama server failed to start on alternate port too!"
    cat /tmp/ollama.log
    exit 1
  fi
  echo "   ✅ Ollama server running on alternate port 11436 (PID: $OLLAMA_PID)"
  # Export the alternate port for downstream scripts
  echo "OLLAMA_PORT=11436" >> "${GITHUB_ENV:-/dev/null}" || true
else
  echo "   ✅ Ollama server running (PID: $OLLAMA_PID)"
fi

# ── Pull the selected model ──────────────────────────────────
echo "📦 Pulling model: $MODEL (source: $MODEL_SOURCE)..."

# Check if model is already cached
if ollama list 2>/dev/null | grep -q "$MODEL"; then
  echo "   ✅ Model $MODEL already available"
else
  ollama pull "$MODEL" 2>&1 || {
    echo "⚠️  Failed to pull $MODEL, trying alternative approaches..."

    if [ "$MODEL_SOURCE" = "ollama-custom" ]; then
      # For custom Ollama models, try without tag first
      BASE_MODEL=$(echo "$MODEL" | cut -d: -f1)
      ollama pull "$BASE_MODEL" 2>&1 || {
        echo "❌ Failed to pull model $MODEL"
        echo ""
        echo "   💡 Popular Ollama models you can try:"
        echo "   ── Chat / General ────────────────────────────"
        echo "   - llama3.2       (3B params, ~2GB download, Meta Llama 3.2)"
        echo "   - llama3.1:8b    (8B params, ~4.7GB download, Meta Llama 3.1)"
        echo "   - mistral        (7B params, ~4.1GB download, Mistral AI)"
        echo "   - phi4           (14B params, ~9GB download, Microsoft Phi-4)"
        echo "   - qwen2.5        (7B params, ~4.4GB download, Alibaba Qwen)"
        echo "   - deepseek-r1:7b (7B params, ~4.7GB download, DeepSeek)"
        echo "   ── Code ─────────────────────────────────────"
        echo "   - codellama      (7B params, ~3.8GB download, Meta Code Llama)"
        echo "   - deepseek-coder-v2 (16B params, ~8.9GB download)"
        echo "   - qwen2.5-coder  (7B params, ~4.4GB download, Alibaba)"
        echo "   ── Small / Fast ─────────────────────────────"
        echo "   - tinyllama      (1.1B params, ~637MB download)"
        echo "   - phi3:mini      (3.8B params, ~2.3GB download, Microsoft)"
        echo "   - gemma3:1b      (1B params, ~815MB download, Google)"
        echo ""
        echo "   💡 Enter the exact Ollama model name (check ollama.com/library)"
        echo "   💡 Larger models (12B+) may not fit in GitHub Actions runners."
        exit 1
      }
    else
      # For Gemma models, try without tag
      BASE_MODEL=$(echo "$MODEL" | cut -d: -f1)
      ollama pull "$BASE_MODEL" 2>&1 || {
        echo "❌ Failed to pull Gemma model $MODEL"
        echo "   Try a smaller model like gemma3:1b"
        exit 1
      }
    fi
  }
  echo "   ✅ Model $MODEL pulled successfully"
fi

# Show model info
echo ""
echo "📋 Model information:"
ollama show "$MODEL" 2>/dev/null | head -15 || echo "   (model info not available)"

# ── Create OpenClaw data directory ──────────────────────────
sudo mkdir -p /home/runner/openclaw-data
sudo chown -R runner:runner /home/runner/openclaw-data

# ── Finished ──────────────────────────────────────────────────
OLLAMA_VERSION=$(ollama --version 2>/dev/null || echo "installed")
echo ""
echo "✅ OpenClaw setup complete!"
echo "   Ollama:   $OLLAMA_VERSION"
echo "   Source:   $MODEL_SOURCE"
echo "   Model:    $MODEL"
echo "   API:      http://localhost:11434"
echo "   Chat UI:  will start on port 11435"
