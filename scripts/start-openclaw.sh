#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Start OpenClaw Server
#  Starts Ollama server + Python web chat UI
#  Supports any Ollama model (custom or Gemma)
#
#  Usage: bash start-openclaw.sh [model] [password] [model_source]
# ============================================================
set -euo pipefail

MODEL="${1:-gemma3:1b}"
INPUT_PASSWORD="${2:-}"
MODEL_SOURCE="${3:-gemma}"
CHAT_PORT=11435
OLLAMA_PORT=11434

echo "🦞 Starting OpenClaw server..."
echo "   Model: $MODEL (source: $MODEL_SOURCE)"

# ── Set password ──────────────────────────────────────────────
if [ -n "$INPUT_PASSWORD" ] && [ ${#INPUT_PASSWORD} -ge 6 ]; then
  AI_PASS="$INPUT_PASSWORD"
else
  if [ -n "$INPUT_PASSWORD" ] && [ ${#INPUT_PASSWORD} -lt 6 ]; then
    echo "⚠️  Password too short (min 6), auto-generating..."
  fi
  AI_PASS=$(openssl rand -base64 12 | tr -d '=/+' | head -c 12)
fi

# Save password
echo "$AI_PASS" > /tmp/ai-password.txt
chmod 600 /tmp/ai-password.txt
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "AI_PASSWORD=$AI_PASS" >> "$GITHUB_ENV"
fi

# ── Kill existing processes ──────────────────────────────────
sudo pkill -9 -f ollama 2>/dev/null || true
pkill -9 -f ollama 2>/dev/null || true
pkill -f "python3.*chat-server" 2>/dev/null || true
pkill -f "python3.*openclaw" 2>/dev/null || true
sleep 2

# Ensure port is free - kill anything still holding it
PORT_PID=$(sudo lsof -ti:$OLLAMA_PORT 2>/dev/null || true)
if [ -n "$PORT_PID" ]; then
  echo "   🔓 Killing process $PORT_PID on port $OLLAMA_PORT..."
  sudo kill -9 $PORT_PID 2>/dev/null || true
  sleep 1
fi

# Use OLLAMA_PORT from env if set (alternate port fallback)
OLLAMA_PORT="${OLLAMA_PORT:-11434}"

# ── Start Ollama server ─────────────────────────────────────
echo "🤖 Starting Ollama inference server on port $OLLAMA_PORT..."
export OLLAMA_HOST="0.0.0.0:$OLLAMA_PORT"
export OLLAMA_MODELS="/home/runner/.ollama/models"
nohup ollama serve > /tmp/ollama-server.log 2>&1 &
OLLAMA_PID=$!
sleep 5

if ! kill -0 $OLLAMA_PID 2>/dev/null; then
  echo "⚠️  Ollama failed to start on port $OLLAMA_PORT, trying port 11436..."
  cat /tmp/ollama-server.log
  OLLAMA_PORT=11436
  export OLLAMA_HOST="0.0.0.0:11436"
  nohup ollama serve > /tmp/ollama-server.log 2>&1 &
  OLLAMA_PID=$!
  sleep 5
  if ! kill -0 $OLLAMA_PID 2>/dev/null; then
    echo "❌ Ollama failed to start on alternate port too!"
    cat /tmp/ollama-server.log
    exit 1
  fi
  echo "   ✅ Ollama running on alternate port 11436 (PID: $OLLAMA_PID)"
  export OLLAMA_PORT=11436
  echo "OLLAMA_PORT=11436" >> "${GITHUB_ENV:-/dev/null}" || true
else
  echo "   ✅ Ollama running (PID: $OLLAMA_PID, port: $OLLAMA_PORT)"
fi

# Wait for Ollama to be ready
echo "   ⏳ Waiting for Ollama API..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:$OLLAMA_PORT/api/tags > /dev/null 2>&1; then
    echo "   ✅ Ollama API is ready"
    break
  fi
  sleep 1
done

# ── Create the web chat UI ──────────────────────────────────
echo "🌐 Creating chat UI..."
mkdir -p /home/runner/openclaw-data

cat > /home/runner/openclaw-data/chat-server.py <<'PYEOF'
#!/usr/bin/env python3
"""
OpenClaw Chat UI Server - Full-featured browser-based interface for any Ollama model
Supports: Gemma, Llama, Mistral, Phi, DeepSeek, Qwen, and any Ollama model
Features: Conversations sidebar, search, agent mode, temperature, system prompts,
          model switching, chat export, streaming responses, model discovery
"""
import asyncio
import json
import os
import time
import hashlib
import uuid
from aiohttp import web

# Configuration
CHAT_PORT = int(os.environ.get("CHAT_PORT", "11435"))
OLLAMA_PORT = int(os.environ.get("OLLAMA_PORT", "11434"))
OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "localhost")
PASSWORD = os.environ.get("AI_PASSWORD", "")
MODEL = os.environ.get("AI_MODEL", "gemma3:1b")
MODEL_SOURCE = os.environ.get("MODEL_SOURCE", "gemma")
CHAT_HISTORY_DIR = os.environ.get("CHAT_HISTORY_DIR", "/home/runner/openclaw-data/history")

# Ensure history directory exists
os.makedirs(CHAT_HISTORY_DIR, exist_ok=True)

# Session tokens (in-memory)
active_sessions = {}

# ── Available Models ──────────────────────────────────────────
GEMMA_MODELS = {
    "gemma4:e2b":   {"family": "Gemma 4", "color": "#8b5cf6", "size": "~5.6GB", "desc": "Latest gen, 2B effective, multimodal"},
    "gemma4:e4b":   {"family": "Gemma 4", "color": "#8b5cf6", "size": "~7.5GB", "desc": "Latest gen, 4B effective, multimodal"},
    "gemma4:26b":   {"family": "Gemma 4", "color": "#8b5cf6", "size": "~9.6GB", "desc": "Latest gen, 26B params, multimodal"},
    "gemma4:31b":   {"family": "Gemma 4", "color": "#8b5cf6", "size": "~18GB",  "desc": "Latest gen, 31B params, multimodal"},
    "gemma3n:e2b":  {"family": "Gemma 3n","color": "#f59e0b", "size": "~5.6GB", "desc": "On-device, 2B effective"},
    "gemma3n:e4b":  {"family": "Gemma 3n","color": "#f59e0b", "size": "~7.5GB", "desc": "On-device, 4B effective"},
    "gemma3:270m":  {"family": "Gemma 3", "color": "#238636", "size": "~292MB", "desc": "Tiny, ultra-fast"},
    "gemma3:1b":    {"family": "Gemma 3", "color": "#238636", "size": "~815MB", "desc": "Fast, lightweight"},
    "gemma3:4b":    {"family": "Gemma 3", "color": "#238636", "size": "~3.3GB",  "desc": "Good balance"},
    "gemma3:12b":   {"family": "Gemma 3", "color": "#238636", "size": "~8.1GB",  "desc": "High quality"},
    "gemma3:27b":   {"family": "Gemma 3", "color": "#238636", "size": "~17GB",   "desc": "Best quality, needs RAM"},
    "gemma2:2b":    {"family": "Gemma 2", "color": "#1f6feb", "size": "~1.6GB",  "desc": "Fast, compact"},
    "gemma2:9b":    {"family": "Gemma 2", "color": "#1f6feb", "size": "~5.4GB",  "desc": "Great quality"},
    "gemma2:27b":   {"family": "Gemma 2", "color": "#1f6feb", "size": "~16GB",   "desc": "Top quality, needs RAM"},
    "gemma:2b":     {"family": "Gemma 1", "color": "#6e7681", "size": "~1.7GB",  "desc": "Original, compact"},
    "gemma:7b":     {"family": "Gemma 1", "color": "#6e7681", "size": "~5.0GB",  "desc": "Original, standard"},
    "codegemma:2b": {"family": "CodeGemma","color":"#da3633","size": "~1.6GB",  "desc": "Code generation, 2B"},
    "codegemma:7b": {"family": "CodeGemma","color":"#da3633","size": "~5.0GB",  "desc": "Code generation, 7B"},
    "shieldgemma:2b":{"family":"ShieldGemma","color":"#6e40c9","size":"~1.7GB", "desc": "Safety classifier, 2B"},
    "shieldgemma:9b":{"family":"ShieldGemma","color":"#6e40c9","size":"~5.8GB", "desc": "Safety classifier, 9B"},
    "shieldgemma:27b":{"family":"ShieldGemma","color":"#6e40c9","size":"~17GB",  "desc": "Safety classifier, 27B"},
}

# Popular non-Gemma Ollama models for reference
POPULAR_OLLAMA_MODELS = {
    "llama3.2":       {"family": "Llama 3.2", "color": "#0ea5e9", "size": "~2GB",   "desc": "Meta Llama 3.2, 3B, fast"},
    "llama3.1:8b":    {"family": "Llama 3.1", "color": "#0ea5e9", "size": "~4.7GB",  "desc": "Meta Llama 3.1, 8B"},
    "llama3:8b":      {"family": "Llama 3",   "color": "#0ea5e9", "size": "~4.7GB",  "desc": "Meta Llama 3, 8B"},
    "mistral":        {"family": "Mistral",   "color": "#f97316", "size": "~4.1GB",  "desc": "Mistral 7B, general purpose"},
    "phi4":           {"family": "Phi",       "color": "#10b981", "size": "~9GB",    "desc": "Microsoft Phi-4, 14B"},
    "phi3:mini":      {"family": "Phi 3",     "color": "#10b981", "size": "~2.3GB",  "desc": "Microsoft Phi-3 Mini, 3.8B"},
    "deepseek-r1:7b": {"family": "DeepSeek",  "color": "#6366f1", "size": "~4.7GB",  "desc": "DeepSeek R1, 7B reasoning"},
    "qwen2.5":        {"family": "Qwen",      "color": "#ec4899", "size": "~4.4GB",  "desc": "Alibaba Qwen 2.5, 7B"},
    "qwen2.5-coder":  {"family": "Qwen Coder","color": "#ec4899", "size": "~4.4GB",  "desc": "Alibaba Qwen Coder, 7B"},
    "codellama":      {"family": "Code Llama","color": "#14b8a6", "size": "~3.8GB",  "desc": "Meta Code Llama, 7B"},
    "tinyllama":      {"family": "TinyLlama", "color": "#a3a3a3", "size": "~637MB",  "desc": "Tiny, 1.1B, ultra-fast"},
}

# Merge all models
ALL_MODELS = {**GEMMA_MODELS, **POPULAR_OLLAMA_MODELS}

# Dynamically discover models from Ollama
def get_available_models():
    """Get list of models actually available on the Ollama server"""
    import urllib.request
    try:
        req = urllib.request.Request(f'http://{OLLAMA_HOST}:{OLLAMA_PORT}/api/tags')
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            return [m['name'] for m in data.get('models', [])]
    except:
        return [MODEL]

HTML_PAGE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>OpenClaw AI Chat</title>
<style>
:root {
  --bg-primary: #0d1117; --bg-secondary: #161b22; --bg-tertiary: #21262d;
  --border: #30363d; --text-primary: #c9d1d9; --text-secondary: #8b949e;
  --accent: #f97316; --green: #238636; --red: #f85149; --purple: #8b5cf6;
  --amber: #f59e0b; --sidebar-w: 280px;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
       background: var(--bg-primary); color: var(--text-primary); height: 100vh;
       display: flex; overflow: hidden; }

/* ── SIDEBAR ──────────────────────────────────────────────── */
.sidebar { width: var(--sidebar-w); background: var(--bg-secondary); border-right: 1px solid var(--border);
           display: flex; flex-direction: column; flex-shrink: 0; transition: width 0.2s; }
.sidebar.collapsed { width: 0; overflow: hidden; border: none; }
.sidebar-header { padding: 12px 16px; border-bottom: 1px solid var(--border);
                  display: flex; align-items: center; gap: 8px; }
.sidebar-header h2 { font-size: 14px; color: var(--accent); flex: 1; }
.btn-icon { background: none; border: 1px solid var(--border); color: var(--text-secondary);
            border-radius: 6px; width: 30px; height: 30px; cursor: pointer;
            display: flex; align-items: center; justify-content: center; font-size: 14px; }
.btn-icon:hover { background: var(--bg-tertiary); color: var(--text-primary); }
.new-chat-btn { margin: 12px; background: var(--accent); color: #fff; border: none;
               padding: 8px 12px; border-radius: 8px; cursor: pointer; font-size: 13px;
               font-weight: 600; text-align: center; }
.new-chat-btn:hover { opacity: 0.9; }
.sidebar-search { margin: 0 12px 8px; }
.sidebar-search input { width: 100%; background: var(--bg-primary); color: var(--text-primary);
  border: 1px solid var(--border); border-radius: 6px; padding: 6px 10px; font-size: 12px; outline: none; }
.sidebar-search input:focus { border-color: var(--accent); }
.conv-list { flex: 1; overflow-y: auto; padding: 4px 8px; }
.conv-item { padding: 8px 12px; border-radius: 6px; cursor: pointer; margin-bottom: 2px;
             font-size: 13px; color: var(--text-secondary); display: flex; align-items: center; gap: 8px;
             transition: background 0.1s; }
.conv-item:hover { background: var(--bg-tertiary); }
.conv-item.active { background: var(--bg-tertiary); color: var(--text-primary); }
.conv-item .conv-icon { font-size: 14px; flex-shrink: 0; }
.conv-item .conv-title { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.conv-item .conv-delete { opacity: 0; background: none; border: none; color: var(--red);
                          cursor: pointer; font-size: 12px; padding: 2px; }
.conv-item:hover .conv-delete { opacity: 1; }
.sidebar-footer { padding: 8px 12px; border-top: 1px solid var(--border); font-size: 11px;
                  color: var(--text-secondary); text-align: center; }

/* ── MAIN AREA ───────────────────────────────────────────── */
.main { flex: 1; display: flex; flex-direction: column; min-width: 0; }
.header { background: var(--bg-secondary); padding: 10px 16px; border-bottom: 1px solid var(--border);
          display: flex; align-items: center; gap: 10px; flex-shrink: 0; }
.header .toggle-sidebar { font-size: 18px; cursor: pointer; color: var(--text-secondary); background: none; border: none; }
.header .toggle-sidebar:hover { color: var(--text-primary); }
.header h1 { font-size: 16px; color: var(--accent); }
.model-badge { padding: 3px 10px; border-radius: 12px; font-size: 11px; font-weight: 600;
               color: #fff; white-space: nowrap; }
.status { margin-left: auto; font-size: 12px; color: var(--text-secondary); }
.status.online { color: #3fb950; }
.status.offline { color: var(--red); }
.header-btns { display: flex; gap: 4px; }

/* ── SETTINGS PANEL ──────────────────────────────────────── */
.settings-panel { background: var(--bg-secondary); border-bottom: 1px solid var(--border);
                  padding: 0; max-height: 0; overflow: hidden; transition: max-height 0.3s, padding 0.3s; }
.settings-panel.open { max-height: 500px; padding: 16px; }
.settings-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
.settings-grid .full-width { grid-column: 1 / -1; }
.setting-group label { display: block; font-size: 11px; color: var(--text-secondary);
                       margin-bottom: 4px; text-transform: uppercase; letter-spacing: 0.5px; }
.setting-group select, .setting-group input, .setting-group textarea {
  width: 100%; background: var(--bg-primary); color: var(--text-primary); border: 1px solid var(--border);
  border-radius: 6px; padding: 6px 10px; font-size: 13px; outline: none; font-family: inherit; }
.setting-group select:focus, .setting-group input:focus, .setting-group textarea:focus { border-color: var(--accent); }
.setting-group textarea { resize: vertical; min-height: 60px; max-height: 120px; }
.range-row { display: flex; align-items: center; gap: 8px; }
.range-row input[type="range"] { flex: 1; }
.range-row .range-val { font-size: 12px; color: var(--accent); min-width: 32px; text-align: right; }
.toggle-row { display: flex; align-items: center; justify-content: space-between; }
.toggle-row span { font-size: 13px; }
.toggle { width: 40px; height: 22px; background: var(--border); border-radius: 11px;
          position: relative; cursor: pointer; transition: background 0.2s; }
.toggle.on { background: var(--green); }
.toggle::after { content: ''; position: absolute; width: 18px; height: 18px; background: #fff;
                 border-radius: 50%; top: 2px; left: 2px; transition: left 0.2s; }
.toggle.on::after { left: 20px; }

/* ── CHAT CONTAINER ──────────────────────────────────────── */
.chat-container { flex: 1; overflow-y: auto; padding: 20px; display: flex;
                  flex-direction: column; gap: 16px; }
.message { max-width: 85%; padding: 12px 16px; border-radius: 12px;
           line-height: 1.6; font-size: 14px; word-wrap: break-word; position: relative; }
.message.user { background: #c2410c; color: #fff; align-self: flex-end;
                border-bottom-right-radius: 4px; }
.message.assistant { background: var(--bg-tertiary); color: var(--text-primary); align-self: flex-start;
                     border-bottom-left-radius: 4px; }
.message.system { background: #1c2128; color: var(--text-secondary); align-self: center;
                  font-style: italic; font-size: 13px; }
.message.agent { background: var(--bg-tertiary); color: var(--text-primary); align-self: flex-start;
                 border-bottom-left-radius: 4px; border-left: 3px solid var(--purple); }
.message pre { background: var(--bg-primary); padding: 10px 14px; border-radius: 6px;
               overflow-x: auto; margin: 8px 0; font-size: 13px; }
.message code { background: var(--bg-primary); padding: 2px 6px; border-radius: 4px; font-size: 13px; }
.message.error { background: #490202; color: var(--red); }
.message .msg-actions { position: absolute; top: 4px; right: 8px; opacity: 0;
                        display: flex; gap: 4px; transition: opacity 0.2s; }
.message:hover .msg-actions { opacity: 1; }
.msg-action-btn { background: none; border: none; color: var(--text-secondary);
                  cursor: pointer; font-size: 12px; padding: 2px 4px; border-radius: 3px; }
.msg-action-btn:hover { background: var(--border); color: var(--text-primary); }
.typing { align-self: flex-start; color: var(--text-secondary); font-size: 13px; padding: 8px 16px; }
.typing span { animation: blink 1.4s infinite; }
.typing span:nth-child(2) { animation-delay: 0.2s; }
.typing span:nth-child(3) { animation-delay: 0.4s; }
@keyframes blink { 0%,100% { opacity: 0.2; } 50% { opacity: 1; } }

/* ── INPUT AREA ──────────────────────────────────────────── */
.input-area { background: var(--bg-secondary); padding: 12px 16px; border-top: 1px solid var(--border);
              display: flex; gap: 10px; flex-shrink: 0; align-items: flex-end; }
.input-area textarea { flex: 1; background: var(--bg-primary); color: var(--text-primary);
                       border: 1px solid var(--border); border-radius: 8px; padding: 10px 14px;
                       font-size: 14px; font-family: inherit; resize: none; outline: none;
                       min-height: 44px; max-height: 150px; }
.input-area textarea:focus { border-color: var(--accent); }
.input-area .send-btn { background: var(--accent); color: #fff; border: none; padding: 10px 20px;
                        border-radius: 8px; font-size: 14px; font-weight: 600;
                        cursor: pointer; white-space: nowrap; }
.input-area .send-btn:hover { opacity: 0.9; }
.input-area .send-btn:disabled { background: var(--bg-tertiary); color: #484f58; cursor: not-allowed; }
.stop-btn { background: var(--red) !important; }
.stop-btn:hover { background: #da3633 !important; }

/* ── INFO BAR ────────────────────────────────────────────── */
.info-bar { display: flex; gap: 12px; padding: 6px 16px; background: var(--bg-secondary);
            border-bottom: 1px solid var(--border); font-size: 11px; color: var(--text-secondary);
            flex-wrap: wrap; align-items: center; }
.info-bar strong { color: var(--text-primary); }
.info-bar a { color: var(--accent); text-decoration: none; }
.info-bar a:hover { text-decoration: underline; }
.agent-indicator { background: var(--purple); color: #fff; padding: 1px 8px;
                   border-radius: 8px; font-size: 10px; font-weight: 600; }

/* ── LOGIN ───────────────────────────────────────────────── */
.login-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0;
                 background: var(--bg-primary); display: flex; align-items: center;
                 justify-content: center; z-index: 100; }
.login-box { background: var(--bg-secondary); padding: 32px; border-radius: 12px;
             border: 1px solid var(--border); width: 380px; text-align: center; }
.login-box h2 { color: var(--accent); margin-bottom: 8px; font-size: 20px; }
.login-box p { color: var(--text-secondary); font-size: 13px; margin-bottom: 20px; }
.login-box input { width: 100%; background: var(--bg-primary); color: var(--text-primary);
                   border: 1px solid var(--border); border-radius: 8px;
                   padding: 10px 14px; font-size: 14px; outline: none; margin-bottom: 12px; }
.login-box input:focus { border-color: var(--accent); }
.login-box button { width: 100%; background: var(--accent); color: #fff; border: none;
                    padding: 10px; border-radius: 8px; font-size: 14px;
                    font-weight: 600; cursor: pointer; }
.login-box button:hover { opacity: 0.9; }
.login-box .error { color: var(--red); font-size: 12px; margin-top: 8px; }

/* ── RESPONSIVE ──────────────────────────────────────────── */
@media (max-width: 768px) {
  .sidebar { position: fixed; z-index: 50; height: 100%; }
  .sidebar.collapsed { width: 0; }
  .message { max-width: 95%; }
  .settings-grid { grid-template-columns: 1fr; }
}
</style>
</head>
<body>

<!-- LOGIN -->
<div class="login-overlay" id="loginOverlay">
  <div class="login-box">
    <h2>🦞 OpenClaw</h2>
    <p>Enter your password to access the AI chat interface</p>
    <input type="password" id="loginPass" placeholder="Password" autofocus
           onkeydown="if(event.key==='Enter')doLogin()">
    <button onclick="doLogin()">Unlock</button>
    <div class="error" id="loginError"></div>
  </div>
</div>

<!-- SIDEBAR -->
<div class="sidebar" id="sidebar">
  <div class="sidebar-header">
    <h2>Conversations</h2>
    <button class="btn-icon" onclick="toggleSidebar()" title="Close sidebar">&#x2715;</button>
  </div>
  <button class="new-chat-btn" onclick="newConversation()">+ New Chat</button>
  <div class="sidebar-search">
    <input type="text" id="convSearch" placeholder="Search conversations..." oninput="filterConversations()">
  </div>
  <div class="conv-list" id="convList"></div>
  <div class="sidebar-footer">
    <span id="convCount">0</span> conversations &middot; <span id="totalMsgCount">0</span> messages
  </div>
</div>

<!-- MAIN -->
<div class="main" id="mainArea">
  <div class="header">
    <button class="toggle-sidebar" onclick="toggleSidebar()" title="Toggle sidebar">&#9776;</button>
    <h1>🦞 OpenClaw</h1>
    <span class="model-badge" id="modelBadge">MODEL</span>
    <span class="status" id="status">Connecting...</span>
    <div class="header-btns">
      <button class="btn-icon" onclick="toggleSettings()" title="Settings">&#9881;</button>
      <button class="btn-icon" onclick="exportChat()" title="Export chat">&#128190;</button>
    </div>
  </div>

  <div class="settings-panel" id="settingsPanel">
    <div class="settings-grid">
      <div class="setting-group full-width">
        <label>Model (type any Ollama model name or select)</label>
        <input type="text" id="modelInput" list="modelList" onchange="switchModel(this.value)" placeholder="e.g. llama3.2, mistral, gemma3:4b, phi4...">
        <datalist id="modelList">
          <option value="gemma4:e2b">Gemma 4 - 2B effective</option>
          <option value="gemma3:1b">Gemma 3 - 1B fast</option>
          <option value="gemma3:4b">Gemma 3 - 4B balanced</option>
          <option value="gemma2:2b">Gemma 2 - 2B compact</option>
          <option value="llama3.2">Llama 3.2 - 3B</option>
          <option value="llama3.1:8b">Llama 3.1 - 8B</option>
          <option value="mistral">Mistral 7B</option>
          <option value="phi4">Phi-4 14B</option>
          <option value="phi3:mini">Phi-3 Mini 3.8B</option>
          <option value="deepseek-r1:7b">DeepSeek R1 7B</option>
          <option value="qwen2.5">Qwen 2.5 7B</option>
          <option value="qwen2.5-coder">Qwen Coder 7B</option>
          <option value="codellama">Code Llama 7B</option>
          <option value="tinyllama">TinyLlama 1.1B</option>
        </datalist>
      </div>
      <div class="setting-group">
        <label>Temperature: <span id="tempVal">0.7</span></label>
        <div class="range-row">
          <input type="range" id="temperature" min="0" max="2" step="0.1" value="0.7"
                 oninput="document.getElementById('tempVal').textContent=this.value">
        </div>
      </div>
      <div class="setting-group">
        <label>Top P: <span id="topPVal">0.9</span></label>
        <div class="range-row">
          <input type="range" id="topP" min="0" max="1" step="0.05" value="0.9"
                 oninput="document.getElementById('topPVal').textContent=this.value">
        </div>
      </div>
      <div class="setting-group">
        <label>Max Tokens</label>
        <input type="number" id="maxTokens" value="2048" min="64" max="32768" step="64">
      </div>
      <div class="setting-group">
        <div class="toggle-row">
          <span>Agent Mode</span>
          <div class="toggle" id="agentToggle" onclick="toggleAgent()"></div>
        </div>
      </div>
      <div class="setting-group full-width">
        <label>System Prompt</label>
        <textarea id="systemPrompt" placeholder="Enter a system prompt...">You are a helpful, harmless, and honest AI assistant.</textarea>
      </div>
      <div class="setting-group">
        <div class="toggle-row">
          <span>Stream Responses</span>
          <div class="toggle on" id="streamToggle" onclick="toggleStream()"></div>
        </div>
      </div>
    </div>
  </div>

  <div class="info-bar">
    <span>Model: <strong id="modelName">-</strong></span>
    <span>Source: <strong id="modelSource">-</strong></span>
    <span>API: <a href="/api" target="_blank">Ollama</a></span>
    <span>Messages: <strong id="msgCount">0</strong></span>
    <span>Session: <strong id="sessionTime">0:00</strong></span>
    <span id="agentIndicator" style="display:none"><span class="agent-indicator">AGENT MODE</span></span>
  </div>

  <div class="chat-container" id="chatContainer">
    <div class="message system">Welcome to OpenClaw! Type a message below to start chatting with any Ollama model. The first response may be slow as the model loads.</div>
  </div>

  <div class="input-area">
    <textarea id="userInput" placeholder="Type your message... (Shift+Enter for new line)"
              rows="1" onkeydown="handleKeydown(event)"></textarea>
    <button class="send-btn" id="sendBtn" onclick="sendMessage()">Send</button>
  </div>
</div>

<script>
const DEFAULT_MODEL = '__MODEL__';
let currentModel = DEFAULT_MODEL;
const MODEL_SOURCE = '__MODEL_SOURCE__';
const OLLAMA_URL = '/api';
let sessionToken = '';
let conversations = [];
let activeConvId = null;
let isGenerating = false;
let sessionStart = Date.now();
let agentMode = false;
let streamMode = true;
let abortController = null;

const input = document.getElementById('userInput');
input.addEventListener('input', () => {
  input.style.height = 'auto';
  input.style.height = Math.min(input.scrollHeight, 150) + 'px';
});

document.getElementById('modelInput').value = currentModel;
updateModelBadge();
loadConversations();

setInterval(() => {
  const elapsed = Math.floor((Date.now() - sessionStart) / 1000);
  const m = Math.floor(elapsed / 60);
  const s = elapsed % 60;
  document.getElementById('sessionTime').textContent = m + ':' + String(s).padStart(2, '0');
}, 1000);

setInterval(checkStatus, 30000);

if (!('__HAS_PASSWORD__' === 'true')) {
  doLoginNoPass();
} else {
  document.getElementById('loginPass').focus();
}

async function doLogin() {
  const pass = document.getElementById('loginPass').value;
  const errEl = document.getElementById('loginError');
  errEl.textContent = '';
  try {
    const res = await fetch('/auth', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({password: pass}) });
    const data = await res.json();
    if (data.ok) { sessionToken = data.token; document.getElementById('loginOverlay').style.display = 'none'; checkStatus(); }
    else { errEl.textContent = data.error || 'Invalid password'; }
  } catch(e) { errEl.textContent = 'Connection error'; }
}

async function doLoginNoPass() {
  try {
    const res = await fetch('/auth', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({password: ''}) });
    const data = await res.json();
    if (data.ok) { sessionToken = data.token; document.getElementById('loginOverlay').style.display = 'none'; checkStatus(); }
  } catch(e) {}
}

async function checkStatus() {
  try {
    const res = await fetch('/status', { headers: {'Authorization': 'Bearer ' + sessionToken} });
    const data = await res.json();
    const statusEl = document.getElementById('status');
    if (data.ollama_running) { statusEl.textContent = 'Online'; statusEl.className = 'status online'; }
    else { statusEl.textContent = 'Offline'; statusEl.className = 'status offline'; }
    // Update model list with available models
    if (data.available_models && data.available_models.length > 0) {
      const datalist = document.getElementById('modelList');
      data.available_models.forEach(m => {
        if (!Array.from(datalist.options).find(o => o.value === m)) {
          const opt = document.createElement('option');
          opt.value = m;
          opt.textContent = m;
          datalist.appendChild(opt);
        }
      });
    }
  } catch(e) {}
}

function newConversation() {
  const conv = { id: 'conv-' + Date.now(), title: 'New Chat', messages: [], model: currentModel, systemPrompt: document.getElementById('systemPrompt').value, temperature: parseFloat(document.getElementById('temperature').value), agentMode: agentMode, createdAt: Date.now(), updatedAt: Date.now() };
  conversations.unshift(conv); activeConvId = conv.id; renderConvList(); renderChat(); saveConversations();
}

function switchConversation(id) {
  activeConvId = id; const conv = getActiveConv();
  if (conv) { currentModel = conv.model || DEFAULT_MODEL; document.getElementById('modelInput').value = currentModel; document.getElementById('systemPrompt').value = conv.systemPrompt || ''; document.getElementById('temperature').value = conv.temperature || 0.7; document.getElementById('tempVal').textContent = conv.temperature || 0.7; agentMode = conv.agentMode || false; updateAgentUI(); updateModelBadge(); }
  renderConvList(); renderChat();
}

function deleteConversation(id, e) { e.stopPropagation(); conversations = conversations.filter(c => c.id !== id); if (activeConvId === id) { activeConvId = conversations.length > 0 ? conversations[0].id : null; } renderConvList(); renderChat(); saveConversations(); }
function getActiveConv() { return conversations.find(c => c.id === activeConvId) || null; }

function renderConvList() {
  const list = document.getElementById('convList');
  const search = document.getElementById('convSearch').value.toLowerCase();
  const filtered = conversations.filter(c => c.title.toLowerCase().includes(search) || c.messages.some(m => m.content.toLowerCase().includes(search)));
  list.innerHTML = filtered.map(c => { const icon = c.agentMode ? '&#129302;' : '&#128172;'; const active = c.id === activeConvId ? 'active' : ''; const msgCount = c.messages.filter(m => m.role === 'user').length; return `<div class="conv-item ${active}" onclick="switchConversation('${c.id}')"><span class="conv-icon">${icon}</span><span class="conv-title">${escapeHtml(c.title)}</span><span style="font-size:10px;color:var(--text-secondary)">${msgCount}</span><button class="conv-delete" onclick="deleteConversation('${c.id}', event)" title="Delete">&#128465;</button></div>`; }).join('');
  document.getElementById('convCount').textContent = conversations.length;
  document.getElementById('totalMsgCount').textContent = conversations.reduce((sum, c) => sum + c.messages.filter(m => m.role === 'user').length, 0);
}

function filterConversations() { renderConvList(); }

function renderChat() {
  const container = document.getElementById('chatContainer'); const conv = getActiveConv();
  if (!conv || conv.messages.length === 0) { container.innerHTML = '<div class="message system">Welcome to OpenClaw! Type a message below to start chatting with any Ollama model.</div>'; document.getElementById('msgCount').textContent = '0'; return; }
  container.innerHTML = conv.messages.map(m => { const cls = m.role === 'user' ? 'user' : (m.role === 'system' ? 'system' : (m.agent ? 'agent' : 'assistant')); return `<div class="message ${cls}"><div class="msg-actions"><button class="msg-action-btn" onclick="copyMessage(this)" title="Copy">&#128203;</button></div>${formatMarkdown(m.content)}</div>`; }).join('');
  document.getElementById('msgCount').textContent = conv.messages.filter(m => m.role === 'user').length; scrollChat();
}

function autoTitle(conv) { const firstMsg = conv.messages.find(m => m.role === 'user'); if (firstMsg) { conv.title = firstMsg.content.substring(0, 50) + (firstMsg.content.length > 50 ? '...' : ''); } }
function saveConversations() { try { localStorage.setItem('openclaw_conversations', JSON.stringify(conversations)); localStorage.setItem('openclaw_active', activeConvId); } catch(e) {} }
function loadConversations() { try { const saved = localStorage.getItem('openclaw_conversations'); if (saved) { conversations = JSON.parse(saved); activeConvId = localStorage.getItem('openclaw_active') || (conversations[0] && conversations[0].id); } } catch(e) {} if (conversations.length === 0) newConversation(); else { switchConversation(activeConvId || conversations[0].id); } renderConvList(); }

function handleKeydown(e) { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); if (!isGenerating) sendMessage(); } }

async function sendMessage() {
  const text = input.value.trim(); if (!text || isGenerating) return;
  if (!activeConvId) newConversation(); const conv = getActiveConv(); if (!conv) return;
  input.value = ''; input.style.height = 'auto'; isGenerating = true;
  const sendBtn = document.getElementById('sendBtn'); sendBtn.textContent = 'Stop'; sendBtn.className = 'send-btn stop-btn'; sendBtn.onclick = stopGeneration;
  const temperature = parseFloat(document.getElementById('temperature').value); const topP = parseFloat(document.getElementById('topP').value); const maxTokens = parseInt(document.getElementById('maxTokens').value); const systemPrompt = document.getElementById('systemPrompt').value;
  conv.messages.push({role: 'user', content: text}); if (conv.messages.filter(m => m.role === 'user').length === 1) autoTitle(conv); renderChat(); renderConvList();
  const apiMessages = []; if (systemPrompt) apiMessages.push({role: 'system', content: systemPrompt}); if (agentMode) apiMessages.push({role: 'system', content: 'You are an autonomous AI agent. Break tasks into steps and reason systematically.'}); apiMessages.push(...conv.messages.filter(m => m.role !== 'system'));
  const typing = document.createElement('div'); typing.className = 'typing'; typing.innerHTML = 'Thinking<span>.</span><span>.</span><span>.</span>'; typing.id = 'typingIndicator'; document.getElementById('chatContainer').appendChild(typing); scrollChat();
  abortController = new AbortController();
  try {
    const chatPayload = { model: currentModel, messages: apiMessages, stream: streamMode, options: { temperature, top_p: topP, num_predict: maxTokens } };
    const res = await fetch('/chat', { method: 'POST', headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + sessionToken}, body: JSON.stringify(chatPayload), signal: abortController.signal });
    const ti = document.getElementById('typingIndicator'); if (ti) ti.remove();
    if (!res.ok) { const err = await res.json().catch(() => ({error: 'Request failed'})); addMessageToConv('assistant', 'Error: ' + (err.error || 'Unknown error'), true); isGenerating = false; resetSendBtn(); return; }
    if (streamMode) { const assistantMsg = addMessageToConv('assistant', '', false, agentMode); let fullText = ''; const reader = res.body.getReader(); const decoder = new TextDecoder(); while (true) { const {done, value} = await reader.read(); if (done) break; const chunk = decoder.decode(value, {stream: true}); const lines = chunk.split('\n').filter(l => l.trim()); for (const line of lines) { try { const data = JSON.parse(line); if (data.message && data.message.content) { fullText += data.message.content; assistantMsg.innerHTML = formatMarkdown(fullText); scrollChat(); } if (data.done) break; } catch(e) {} } } conv.messages[conv.messages.length - 1].content = fullText; }
    else { const data = await res.json(); const content = data.message?.content || data.response || ''; addMessageToConv('assistant', content, false, agentMode); }
    document.getElementById('msgCount').textContent = conv.messages.filter(m => m.role === 'user').length;
  } catch(e) { const ti = document.getElementById('typingIndicator'); if (ti) ti.remove(); if (e.name === 'AbortError') addMessageToConv('system', 'Generation stopped.'); else addMessageToConv('assistant', 'Connection error: ' + e.message, true); }
  isGenerating = false; abortController = null; resetSendBtn(); saveConversations(); input.focus();
}

function stopGeneration() { if (abortController) abortController.abort(); }
function resetSendBtn() { const sendBtn = document.getElementById('sendBtn'); sendBtn.textContent = 'Send'; sendBtn.className = 'send-btn'; sendBtn.onclick = sendMessage; }

function addMessageToConv(role, content, isError, isAgent) {
  const conv = getActiveConv(); if (!conv) return null;
  if (role !== 'system') conv.messages.push({role, content, agent: isAgent});
  const container = document.getElementById('chatContainer'); const div = document.createElement('div');
  let cls = role; if (isError) cls = 'error'; else if (isAgent && role === 'assistant') cls = 'agent'; else if (role === 'system') cls = 'system';
  div.className = 'message ' + cls; div.innerHTML = `<div class="msg-actions"><button class="msg-action-btn" onclick="copyMessage(this)" title="Copy">&#128203;</button></div>` + formatMarkdown(content); container.appendChild(div); scrollChat(); return div;
}

function toggleSidebar() { document.getElementById('sidebar').classList.toggle('collapsed'); }
function toggleSettings() { document.getElementById('settingsPanel').classList.toggle('open'); }
function toggleAgent() { const toggle = document.getElementById('agentToggle'); agentMode = !agentMode; toggle.classList.toggle('on', agentMode); document.getElementById('agentIndicator').style.display = agentMode ? 'inline' : 'none'; const conv = getActiveConv(); if (conv) conv.agentMode = agentMode; saveConversations(); }
function updateAgentUI() { const toggle = document.getElementById('agentToggle'); toggle.classList.toggle('on', agentMode); document.getElementById('agentIndicator').style.display = agentMode ? 'inline' : 'none'; }
function toggleStream() { const toggle = document.getElementById('streamToggle'); streamMode = !streamMode; toggle.classList.toggle('on', streamMode); }

function switchModel(model) { currentModel = model; updateModelBadge(); const conv = getActiveConv(); if (conv) conv.model = model; saveConversations(); }

function updateModelBadge() {
  const badge = document.getElementById('modelBadge');
  const info = { gemma4: {family: 'Gemma 4', color: '#8b5cf6'}, gemma3n: {family: 'Gemma 3n', color: '#f59e0b'}, gemma3: {family: 'Gemma 3', color: '#238636'}, gemma2: {family: 'Gemma 2', color: '#1f6feb'}, codegemma: {family: 'CodeGemma', color: '#da3633'}, shieldgemma: {family: 'ShieldGemma', color: '#6e40c9'}, gemma: {family: 'Gemma', color: '#6e7681'}, llama: {family: 'Llama', color: '#0ea5e9'}, mistral: {family: 'Mistral', color: '#f97316'}, phi: {family: 'Phi', color: '#10b981'}, deepseek: {family: 'DeepSeek', color: '#6366f1'}, qwen: {family: 'Qwen', color: '#ec4899'}, codellama: {family: 'Code Llama', color: '#14b8a6'}, tinyllama: {family: 'TinyLlama', color: '#a3a3a3'} };
  let found = null; for (const [key, val] of Object.entries(info)) { if (currentModel.startsWith(key)) { found = val; break; } }
  if (found) { badge.style.background = found.color; badge.textContent = found.family + ' \u2022 ' + currentModel; } else { badge.style.background = '#f97316'; badge.textContent = currentModel; }
  document.getElementById('modelName').textContent = badge.textContent;
  document.getElementById('modelSource').textContent = MODEL_SOURCE === 'ollama-custom' ? 'Ollama' : 'Gemma';
}

function scrollChat() { const c = document.getElementById('chatContainer'); c.scrollTop = c.scrollHeight; }

function escapeHtml(text) { const div = document.createElement('div'); div.textContent = text; return div.innerHTML; }

function formatMarkdown(text) {
  if (!text) return '';
  let html = escapeHtml(text);
  html = html.replace(/```(\w*)\n([\s\S]*?)```/g, '<pre><code>$2</code></pre>');
  html = html.replace(/`([^`]+)`/g, '<code>$1</code>');
  html = html.replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>');
  html = html.replace(/\*([^*]+)\*/g, '<i>$1</i>');
  html = html.replace(/\n/g, '<br>');
  return html;
}

function copyMessage(btn) { const msg = btn.closest('.message'); const text = msg.textContent.replace('📋', '').trim(); navigator.clipboard.writeText(text).then(() => { btn.textContent = '✓'; setTimeout(() => btn.textContent = '📋', 1000); }); }

function exportChat() { const conv = getActiveConv(); if (!conv) return; const data = { model: conv.model, messages: conv.messages, exported: new Date().toISOString() }; const blob = new Blob([JSON.stringify(data, null, 2)], {type: 'application/json'}); const url = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = url; a.download = `openclaw-chat-${Date.now()}.json`; a.click(); URL.revokeObjectURL(url); }
</script>
</body>
</html>
"""

# ── Routes ────────────────────────────────────────────────────

async def handle_index(request):
    html = HTML_PAGE.replace('__MODEL__', MODEL)
    html = html.replace('__MODEL_SOURCE__', MODEL_SOURCE)
    html = html.replace('__HAS_PASSWORD__', 'true' if PASSWORD else 'false')
    return web.Response(text=html, content_type='text/html')

async def handle_auth(request):
    data = await request.json()
    pw = data.get('password', '')
    if PASSWORD and pw != PASSWORD:
        return web.json_response({'ok': False, 'error': 'Invalid password'})
    token = hashlib.sha256(f"{pw}:{time.time()}".encode()).hexdigest()[:32]
    active_sessions[token] = time.time()
    return web.json_response({'ok': True, 'token': token})

async def handle_status(request):
    import urllib.request
    ollama_running = False
    available_models = []
    try:
        req = urllib.request.Request(f'http://{OLLAMA_HOST}:{OLLAMA_PORT}/api/tags')
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            ollama_running = True
            available_models = [m['name'] for m in data.get('models', [])]
    except:
        pass
    return web.json_response({
        'ollama_running': ollama_running,
        'model': MODEL,
        'model_source': MODEL_SOURCE,
        'available_models': available_models
    })

async def handle_chat(request):
    import urllib.request
    data = await request.json()
    model = data.get('model', MODEL)

    if data.get('stream'):
        resp = await web.StreamResponse()
        resp.content_type = 'text/event-stream'
        await resp.prepare(request)

        payload = json.dumps(data).encode()
        req = urllib.request.Request(
            f'http://{OLLAMA_HOST}:{OLLAMA_PORT}/api/chat',
            data=payload,
            headers={'Content-Type': 'application/json'}
        )
        with urllib.request.urlopen(req) as api_resp:
            while True:
                chunk = api_resp.read(512)
                if not chunk:
                    break
                await resp.write(chunk)
        await resp.write_eof()
        return resp
    else:
        payload = json.dumps(data).encode()
        req = urllib.request.Request(
            f'http://{OLLAMA_HOST}:{OLLAMA_PORT}/api/chat',
            data=payload,
            headers={'Content-Type': 'application/json'}
        )
        with urllib.request.urlopen(req) as api_resp:
            result = api_resp.read().decode()
        return web.Response(text=result, content_type='application/json')

async def handle_api_proxy(request):
    """Proxy any /api/* request to Ollama"""
    import urllib.request
    path = request.match_info.get('path', '')
    ollama_url = f'http://{OLLAMA_HOST}:{OLLAMA_PORT}/api/{path}'

    if request.method == 'GET':
        req = urllib.request.Request(ollama_url)
    else:
        body = await request.read()
        req = urllib.request.Request(ollama_url, data=body, headers={'Content-Type': 'application/json'})

    try:
        with urllib.request.urlopen(req) as resp:
            return web.Response(text=resp.read().decode(), content_type='application/json')
    except Exception as e:
        return web.json_response({'error': str(e)}, status=500)

# ── App Setup ────────────────────────────────────────────────
app = web.Application()
app.router.add_get('/', handle_index)
app.router.add_post('/auth', handle_auth)
app.router.add_get('/status', handle_status)
app.router.add_post('/chat', handle_chat)
app.router.add_route('*', '/api/{path:.*}', handle_api_proxy)

if __name__ == '__main__':
    print(f"🦞 OpenClaw Chat UI starting on port {CHAT_PORT}")
    print(f"   Model: {MODEL} (source: {MODEL_SOURCE})")
    print(f"   Ollama API: http://{OLLAMA_HOST}:{OLLAMA_PORT}")
    web.run_app(app, host='0.0.0.0', port=CHAT_PORT, print=None)
PYEOF

# ── Start the chat server ───────────────────────────────────
echo "🦞 Starting OpenClaw chat UI..."
export AI_PASSWORD="$AI_PASS"
export AI_MODEL="$MODEL"
export AI_MODELS="$MODEL"
export MODEL_SOURCE="$MODEL_SOURCE"
export CHAT_PORT="$CHAT_PORT"
export OLLAMA_PORT="$OLLAMA_PORT"
export OLLAMA_HOST="localhost"
export CHAT_HISTORY_DIR="/home/runner/openclaw-data/history"

nohup python3 /home/runner/openclaw-data/chat-server.py > /tmp/openclaw-chat-server.log 2>&1 &
CHAT_PID=$!
sleep 3

# Verify chat server started
if kill -0 $CHAT_PID 2>/dev/null; then
  echo "   ✅ Chat UI running (PID: $CHAT_PID, port: $CHAT_PORT)"
else
  echo "❌ Chat UI failed to start!"
  cat /tmp/openclaw-chat-server.log
  exit 1
fi

echo ""
echo "✅ OpenClaw server is ready!"
echo "   Model:     $MODEL"
echo "   Source:    $MODEL_SOURCE"
echo "   Ollama:    http://localhost:$OLLAMA_PORT"
echo "   Chat UI:   http://localhost:$CHAT_PORT"
echo "   Password:  $AI_PASS"
