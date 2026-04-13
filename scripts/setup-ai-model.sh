#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Setup AI Model Environment
#  Installs Ollama, pulls the selected Gemma model,
#  and sets up the web chat UI
#  First run: ~3-5 min (model download), cached: ~30 sec
# ============================================================
set -euo pipefail

MODEL="${1:-gemma3:1b}"
CACHE_DIR="/tmp/ai-cache"
DEBS_DIR="$CACHE_DIR/debs"

mkdir -p "$DEBS_DIR"

echo "🤖 Setting up AI model environment..."
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
    # Fallback: download binary directly
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

# ── Start Ollama server (needed for model pull) ──────────────
echo "🚀 Starting Ollama server for model pull..."
pkill -f ollama 2>/dev/null || true
sleep 1

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
  echo "❌ Ollama server failed to start!"
  cat /tmp/ollama.log
  exit 1
fi
echo "   ✅ Ollama server running (PID: $OLLAMA_PID)"

# ── Pull the selected Gemma model ────────────────────────────
echo "📦 Pulling model: $MODEL (this may take a few minutes on first run)..."

# Check if model is already cached
if ollama list 2>/dev/null | grep -q "$MODEL"; then
  echo "   ✅ Model $MODEL already available"
else
  ollama pull "$MODEL" 2>&1 || {
    echo "⚠️  Failed to pull $MODEL, trying alternative names..."
    # Try without tag
    BASE_MODEL=$(echo "$MODEL" | cut -d: -f1)
    ollama pull "$BASE_MODEL" 2>&1 || {
      echo "❌ Failed to pull model $MODEL"
      echo "   Available Gemma models:"
      echo "   ── Gemma 4 (Latest) ──────────────────────"
      echo "   - gemma4:e2b   (2B effective, ~5.6GB download)"
      echo "   - gemma4:e4b   (4B effective, ~7.5GB download)"
      echo "   - gemma4:26b   (26B params, ~9.6GB download)"
      echo "   - gemma4:31b   (31B params, ~18GB download)"
      echo "   ── Gemma 3n (On-device) ──────────────────"
      echo "   - gemma3n:e2b  (2B effective, ~5.6GB download)"
      echo "   - gemma3n:e4b  (4B effective, ~7.5GB download)"
      echo "   ── Gemma 3 ──────────────────────────────"
      echo "   - gemma3:270m  (270M params, ~292MB download)"
      echo "   - gemma3:1b    (1B params, ~815MB download)"
      echo "   - gemma3:4b    (4B params, ~3.3GB download)"
      echo "   - gemma3:12b   (12B params, ~8.1GB download)"
      echo "   - gemma3:27b   (27B params, ~17GB download)"
      echo "   ── Gemma 2 ──────────────────────────────"
      echo "   - gemma2:2b    (2B params, ~1.6GB download)"
      echo "   - gemma2:9b    (9B params, ~5.4GB download)"
      echo "   - gemma2:27b   (27B params, ~16GB download)"
      echo "   ── Gemma 1 ──────────────────────────────"
      echo "   - gemma:2b     (2B params, ~1.7GB download)"
      echo "   - gemma:7b     (7B params, ~5.0GB download)"
      echo "   ── CodeGemma (Code) ─────────────────────"
      echo "   - codegemma:2b (2B params, ~1.6GB download)"
      echo "   - codegemma:7b (7B params, ~5.0GB download)"
      echo "   ── ShieldGemma (Safety) ─────────────────"
      echo "   - shieldgemma:2b  (2B params, ~1.7GB download)"
      echo "   - shieldgemma:9b  (9B params, ~5.8GB download)"
      echo "   - shieldgemma:27b (27B params, ~17GB download)"
      echo ""
      echo "   💡 Larger models (12B+) may not fit in GitHub Actions runners."
      echo "   💡 Recommended for GHA: gemma3:1b, gemma3:4b, gemma3n:e2b, gemma4:e2b"
      exit 1
    }
  }
  echo "   ✅ Model $MODEL pulled successfully"
fi

# Show model info
echo ""
echo "📋 Model information:"
ollama show "$MODEL" 2>/dev/null | head -15 || echo "   (model info not available)"

# ── Create AI data directory ────────────────────────────────
sudo mkdir -p /home/runner/ai-data
sudo chown -R runner:runner /home/runner/ai-data

# ── Finished ──────────────────────────────────────────────────
OLLAMA_VERSION=$(ollama --version 2>/dev/null || echo "installed")
echo ""
echo "✅ AI model setup complete!"
echo "   Ollama:   $OLLAMA_VERSION"
echo "   Model:    $MODEL"
echo "   API:      http://localhost:11434"
echo "   Chat UI:  will start on port 11435"
