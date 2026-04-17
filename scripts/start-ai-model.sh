#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Start AI Model Server
#  Starts Ollama server + Python web chat UI
#  Provides a browser-based chat interface for Gemma models
#
#  Usage: bash start-ai-model.sh [model] [password]
# ============================================================
set -euo pipefail

MODEL="${1:-gemma3:1b}"
INPUT_PASSWORD="${2:-}"
CHAT_PORT=11435
OLLAMA_PORT=11434

echo "🚀 Starting AI model server..."

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
pkill -f "python3.*ai-chat" 2>/dev/null || true
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
mkdir -p /home/runner/ai-data

cat > /home/runner/ai-data/chat-server.py <<'PYEOF'
#!/usr/bin/env python3
"""
AI Chat UI Server - Full-featured browser-based interface for Ollama/Gemma models
Features: Conversations sidebar, search, agent mode, temperature, system prompts,
          model switching, chat export, streaming responses
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
CHAT_HISTORY_DIR = os.environ.get("CHAT_HISTORY_DIR", "/home/runner/ai-data/history")

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

HTML_PAGE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>AI Chat - Gemma</title>
<style>
:root {
  --bg-primary: #0d1117; --bg-secondary: #161b22; --bg-tertiary: #21262d;
  --border: #30363d; --text-primary: #c9d1d9; --text-secondary: #8b949e;
  --accent: #58a6ff; --green: #238636; --red: #f85149; --purple: #8b5cf6;
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
.new-chat-btn { margin: 12px; background: var(--green); color: #fff; border: none;
               padding: 8px 12px; border-radius: 8px; cursor: pointer; font-size: 13px;
               font-weight: 600; text-align: center; }
.new-chat-btn:hover { background: #2ea043; }
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
.settings-panel.open { max-height: 400px; padding: 16px; }
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

/* ── SEARCH BAR ──────────────────────────────────────────── */
.search-bar { background: var(--bg-secondary); border-bottom: 1px solid var(--border);
              padding: 0; max-height: 0; overflow: hidden; transition: max-height 0.2s, padding 0.2s; }
.search-bar.open { max-height: 50px; padding: 8px 16px; display: flex; gap: 8px; align-items: center; }
.search-bar input { flex: 1; background: var(--bg-primary); color: var(--text-primary);
                    border: 1px solid var(--border); border-radius: 6px; padding: 6px 12px; font-size: 13px; outline: none; }
.search-bar input:focus { border-color: var(--accent); }
.search-bar .search-count { font-size: 12px; color: var(--text-secondary); white-space: nowrap; }
.search-bar button { background: var(--bg-tertiary); color: var(--text-primary); border: 1px solid var(--border);
                     border-radius: 6px; padding: 4px 10px; font-size: 12px; cursor: pointer; }
.search-bar button:hover { background: var(--border); }
.search-highlight { background: rgba(210,153,34,0.4); border-radius: 2px; padding: 0 1px; }

/* ── CHAT CONTAINER ──────────────────────────────────────── */
.chat-container { flex: 1; overflow-y: auto; padding: 20px; display: flex;
                  flex-direction: column; gap: 16px; }
.message { max-width: 85%; padding: 12px 16px; border-radius: 12px;
           line-height: 1.6; font-size: 14px; word-wrap: break-word; position: relative; }
.message.user { background: #1f6feb; color: #fff; align-self: flex-end;
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
.input-area .send-btn { background: var(--green); color: #fff; border: none; padding: 10px 20px;
                        border-radius: 8px; font-size: 14px; font-weight: 600;
                        cursor: pointer; white-space: nowrap; }
.input-area .send-btn:hover { background: #2ea043; }
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
.login-box button { width: 100%; background: var(--green); color: #fff; border: none;
                    padding: 10px; border-radius: 8px; font-size: 14px;
                    font-weight: 600; cursor: pointer; }
.login-box button:hover { background: #2ea043; }
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
    <h2>AI Chat</h2>
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
  <!-- HEADER -->
  <div class="header">
    <button class="toggle-sidebar" onclick="toggleSidebar()" title="Toggle sidebar">&#9776;</button>
    <h1>AI Chat</h1>
    <span class="model-badge" id="modelBadge">MODEL</span>
    <span class="status" id="status">Connecting...</span>
    <div class="header-btns">
      <button class="btn-icon" onclick="toggleSearch()" title="Search chat">&#128269;</button>
      <button class="btn-icon" onclick="toggleSettings()" title="Settings">&#9881;</button>
      <button class="btn-icon" onclick="exportChat()" title="Export chat">&#128190;</button>
    </div>
  </div>

  <!-- SEARCH -->
  <div class="search-bar" id="searchBar">
    <input type="text" id="chatSearchInput" placeholder="Search in current conversation..." oninput="searchChat()">
    <span class="search-count" id="searchCount"></span>
    <button onclick="clearSearch()">Clear</button>
  </div>

  <!-- SETTINGS -->
  <div class="settings-panel" id="settingsPanel">
    <div class="settings-grid">
      <div class="setting-group">
        <label>Model</label>
        <select id="modelSelect" onchange="switchModel(this.value)">
          <optgroup label="Gemma 4 (Latest)">
            <option value="gemma4:e2b">gemma4:e2b - 2B effective</option>
            <option value="gemma4:e4b">gemma4:e4b - 4B effective</option>
            <option value="gemma4:26b">gemma4:26b - 26B params</option>
            <option value="gemma4:31b">gemma4:31b - 31B params</option>
          </optgroup>
          <optgroup label="Gemma 3n (On-device)">
            <option value="gemma3n:e2b">gemma3n:e2b - 2B effective</option>
            <option value="gemma3n:e4b">gemma3n:e4b - 4B effective</option>
          </optgroup>
          <optgroup label="Gemma 3">
            <option value="gemma3:270m">gemma3:270m - Ultra tiny</option>
            <option value="gemma3:1b">gemma3:1b - Fast</option>
            <option value="gemma3:4b">gemma3:4b - Balanced</option>
            <option value="gemma3:12b">gemma3:12b - High quality</option>
            <option value="gemma3:27b">gemma3:27b - Best quality</option>
          </optgroup>
          <optgroup label="Gemma 2">
            <option value="gemma2:2b">gemma2:2b - Compact</option>
            <option value="gemma2:9b">gemma2:9b - Great quality</option>
            <option value="gemma2:27b">gemma2:27b - Top quality</option>
          </optgroup>
          <optgroup label="CodeGemma (Code)">
            <option value="codegemma:2b">codegemma:2b - Code 2B</option>
            <option value="codegemma:7b">codegemma:7b - Code 7B</option>
          </optgroup>
          <optgroup label="ShieldGemma (Safety)">
            <option value="shieldgemma:2b">shieldgemma:2b - Safety 2B</option>
            <option value="shieldgemma:9b">shieldgemma:9b - Safety 9B</option>
            <option value="shieldgemma:27b">shieldgemma:27b - Safety 27B</option>
          </optgroup>
        </select>
      </div>
      <div class="setting-group">
        <label>Temperature: <span id="tempVal">0.7</span></label>
        <div class="range-row">
          <input type="range" id="temperature" min="0" max="2" step="0.1" value="0.7"
                 oninput="document.getElementById('tempVal').textContent=this.value">
          <span class="range-val" id="tempDisplay">0.7</span>
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
      <div class="setting-group full-width">
        <label>System Prompt</label>
        <textarea id="systemPrompt" placeholder="Enter a system prompt to customize the AI's behavior...">You are a helpful, harmless, and honest AI assistant.</textarea>
      </div>
      <div class="setting-group">
        <div class="toggle-row">
          <span>Agent Mode</span>
          <div class="toggle" id="agentToggle" onclick="toggleAgent()"></div>
        </div>
      </div>
      <div class="setting-group">
        <div class="toggle-row">
          <span>Stream Responses</span>
          <div class="toggle on" id="streamToggle" onclick="toggleStream()"></div>
        </div>
      </div>
    </div>
  </div>

  <!-- INFO BAR -->
  <div class="info-bar">
    <span>Model: <strong id="modelName">-</strong></span>
    <span>API: <a href="/api" target="_blank">Ollama</a></span>
    <span>Messages: <strong id="msgCount">0</strong></span>
    <span>Session: <strong id="sessionTime">0:00</strong></span>
    <span id="agentIndicator" style="display:none"><span class="agent-indicator">AGENT MODE</span></span>
  </div>

  <!-- CHAT -->
  <div class="chat-container" id="chatContainer">
    <div class="message system">Welcome! Type a message below to start chatting. The first response may be slow as the model loads.</div>
  </div>

  <!-- INPUT -->
  <div class="input-area">
    <textarea id="userInput" placeholder="Type your message... (Shift+Enter for new line)"
              rows="1" onkeydown="handleKeydown(event)"></textarea>
    <button class="send-btn" id="sendBtn" onclick="sendMessage()">Send</button>
  </div>
</div>

<script>
const DEFAULT_MODEL = '__MODEL__';
let currentModel = DEFAULT_MODEL;
const OLLAMA_URL = '/api';
let sessionToken = '';
let conversations = [];
let activeConvId = null;
let isGenerating = false;
let sessionStart = Date.now();
let agentMode = false;
let streamMode = true;
let abortController = null;

// ── INIT ────────────────────────────────────────────────────
const input = document.getElementById('userInput');
input.addEventListener('input', () => {
  input.style.height = 'auto';
  input.style.height = Math.min(input.scrollHeight, 150) + 'px';
});

// Set default model in selector
document.getElementById('modelSelect').value = currentModel;

// Color-code the model badge
updateModelBadge();

// Load conversations from localStorage
loadConversations();

// Session timer
setInterval(() => {
  const elapsed = Math.floor((Date.now() - sessionStart) / 1000);
  const m = Math.floor(elapsed / 60);
  const s = elapsed % 60;
  document.getElementById('sessionTime').textContent = m + ':' + String(s).padStart(2, '0');
}, 1000);

// Check status periodically
setInterval(checkStatus, 30000);

// Auto-login if no password
if (!('__HAS_PASSWORD__' === 'true')) {
  doLoginNoPass();
} else {
  document.getElementById('loginPass').focus();
}

// ── AUTH ─────────────────────────────────────────────────────
async function doLogin() {
  const pass = document.getElementById('loginPass').value;
  const errEl = document.getElementById('loginError');
  errEl.textContent = '';
  try {
    const res = await fetch('/auth', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({password: pass})
    });
    const data = await res.json();
    if (data.ok) {
      sessionToken = data.token;
      document.getElementById('loginOverlay').style.display = 'none';
      checkStatus();
    } else {
      errEl.textContent = data.error || 'Invalid password';
    }
  } catch(e) { errEl.textContent = 'Connection error'; }
}

async function doLoginNoPass() {
  try {
    const res = await fetch('/auth', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({password: ''})
    });
    const data = await res.json();
    if (data.ok) {
      sessionToken = data.token;
      document.getElementById('loginOverlay').style.display = 'none';
      checkStatus();
    }
  } catch(e) {}
}

// ── STATUS ───────────────────────────────────────────────────
async function checkStatus() {
  try {
    const res = await fetch('/status', { headers: {'Authorization': 'Bearer ' + sessionToken} });
    const data = await res.json();
    const statusEl = document.getElementById('status');
    if (data.ollama_running) {
      statusEl.textContent = 'Online';
      statusEl.className = 'status online';
    } else {
      statusEl.textContent = 'Offline';
      statusEl.className = 'status offline';
    }
  } catch(e) {}
}

// ── CONVERSATIONS ────────────────────────────────────────────
function newConversation() {
  const conv = {
    id: 'conv-' + Date.now(),
    title: 'New Chat',
    messages: [],
    model: currentModel,
    systemPrompt: document.getElementById('systemPrompt').value,
    temperature: parseFloat(document.getElementById('temperature').value),
    agentMode: agentMode,
    createdAt: Date.now(),
    updatedAt: Date.now()
  };
  conversations.unshift(conv);
  activeConvId = conv.id;
  renderConvList();
  renderChat();
  saveConversations();
}

function switchConversation(id) {
  activeConvId = id;
  const conv = getActiveConv();
  if (conv) {
    currentModel = conv.model || DEFAULT_MODEL;
    document.getElementById('modelSelect').value = currentModel;
    document.getElementById('systemPrompt').value = conv.systemPrompt || '';
    document.getElementById('temperature').value = conv.temperature || 0.7;
    document.getElementById('tempVal').textContent = conv.temperature || 0.7;
    agentMode = conv.agentMode || false;
    updateAgentUI();
    updateModelBadge();
  }
  renderConvList();
  renderChat();
}

function deleteConversation(id, e) {
  e.stopPropagation();
  conversations = conversations.filter(c => c.id !== id);
  if (activeConvId === id) {
    activeConvId = conversations.length > 0 ? conversations[0].id : null;
  }
  renderConvList();
  renderChat();
  saveConversations();
}

function getActiveConv() {
  return conversations.find(c => c.id === activeConvId) || null;
}

function renderConvList() {
  const list = document.getElementById('convList');
  const search = document.getElementById('convSearch').value.toLowerCase();
  const filtered = conversations.filter(c =>
    c.title.toLowerCase().includes(search) ||
    c.messages.some(m => m.content.toLowerCase().includes(search))
  );
  list.innerHTML = filtered.map(c => {
    const icon = c.agentMode ? '&#129302;' : '&#128172;';
    const active = c.id === activeConvId ? 'active' : '';
    const msgCount = c.messages.filter(m => m.role === 'user').length;
    return `<div class="conv-item ${active}" onclick="switchConversation('${c.id}')">
      <span class="conv-icon">${icon}</span>
      <span class="conv-title">${escapeHtml(c.title)}</span>
      <span style="font-size:10px;color:var(--text-secondary)">${msgCount}</span>
      <button class="conv-delete" onclick="deleteConversation('${c.id}', event)" title="Delete">&#128465;</button>
    </div>`;
  }).join('');
  document.getElementById('convCount').textContent = conversations.length;
  const totalMsgs = conversations.reduce((sum, c) => sum + c.messages.filter(m => m.role === 'user').length, 0);
  document.getElementById('totalMsgCount').textContent = totalMsgs;
}

function filterConversations() { renderConvList(); }

function renderChat() {
  const container = document.getElementById('chatContainer');
  const conv = getActiveConv();
  if (!conv || conv.messages.length === 0) {
    container.innerHTML = '<div class="message system">Welcome! Type a message below to start chatting. The first response may be slow as the model loads.</div>';
    document.getElementById('msgCount').textContent = '0';
    return;
  }
  container.innerHTML = conv.messages.map(m => {
    const cls = m.role === 'user' ? 'user' : (m.role === 'system' ? 'system' : (m.agent ? 'agent' : 'assistant'));
    return `<div class="message ${cls}">
      <div class="msg-actions">
        <button class="msg-action-btn" onclick="copyMessage(this)" title="Copy">&#128203;</button>
      </div>
      ${formatMarkdown(m.content)}
    </div>`;
  }).join('');
  document.getElementById('msgCount').textContent = conv.messages.filter(m => m.role === 'user').length;
  scrollChat();
}

function autoTitle(conv) {
  const firstMsg = conv.messages.find(m => m.role === 'user');
  if (firstMsg) {
    conv.title = firstMsg.content.substring(0, 50) + (firstMsg.content.length > 50 ? '...' : '');
  }
}

function saveConversations() {
  try {
    localStorage.setItem('ai_chat_conversations', JSON.stringify(conversations));
    localStorage.setItem('ai_chat_active', activeConvId);
  } catch(e) {}
}

function loadConversations() {
  try {
    const saved = localStorage.getItem('ai_chat_conversations');
    if (saved) {
      conversations = JSON.parse(saved);
      activeConvId = localStorage.getItem('ai_chat_active') || (conversations[0] && conversations[0].id);
    }
  } catch(e) {}
  if (conversations.length === 0) newConversation();
  else {
    switchConversation(activeConvId || conversations[0].id);
  }
  renderConvList();
}

// ── SEND MESSAGE ─────────────────────────────────────────────
function handleKeydown(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    if (isGenerating) return;
    sendMessage();
  }
}

async function sendMessage() {
  const text = input.value.trim();
  if (!text || isGenerating) return;

  // Ensure we have an active conversation
  if (!activeConvId) newConversation();
  const conv = getActiveConv();
  if (!conv) return;

  input.value = '';
  input.style.height = 'auto';
  isGenerating = true;

  const sendBtn = document.getElementById('sendBtn');
  sendBtn.textContent = 'Stop';
  sendBtn.className = 'send-btn stop-btn';
  sendBtn.onclick = stopGeneration;

  // Get settings
  const temperature = parseFloat(document.getElementById('temperature').value);
  const topP = parseFloat(document.getElementById('topP').value);
  const maxTokens = parseInt(document.getElementById('maxTokens').value);
  const systemPrompt = document.getElementById('systemPrompt').value;

  // Add user message
  conv.messages.push({role: 'user', content: text});
  if (conv.messages.filter(m => m.role === 'user').length === 1) autoTitle(conv);
  renderChat();
  renderConvList();

  // Build messages array for API
  const apiMessages = [];
  if (systemPrompt) {
    apiMessages.push({role: 'system', content: systemPrompt});
  }
  // Agent mode: add extra system instructions
  if (agentMode) {
    apiMessages.push({role: 'system', content: 'You are an autonomous AI agent. When the user asks you to do something, break it down into steps and reason through them systematically. Use thinking blocks to plan your approach. Be thorough and methodical.'});
  }
  apiMessages.push(...conv.messages.filter(m => m.role !== 'system'));

  // Show typing indicator
  const typing = document.createElement('div');
  typing.className = 'typing';
  typing.innerHTML = 'Thinking<span>.</span><span>.</span><span>.</span>';
  typing.id = 'typingIndicator';
  document.getElementById('chatContainer').appendChild(typing);
  scrollChat();

  abortController = new AbortController();

  try {
    const chatPayload = {
      model: currentModel,
      messages: apiMessages,
      stream: streamMode,
      options: {
        temperature: temperature,
        top_p: topP,
        num_predict: maxTokens
      }
    };

    const res = await fetch('/chat', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + sessionToken
      },
      body: JSON.stringify(chatPayload),
      signal: abortController.signal
    });

    // Remove typing indicator
    const ti = document.getElementById('typingIndicator');
    if (ti) ti.remove();

    if (!res.ok) {
      const err = await res.json().catch(() => ({error: 'Request failed'}));
      addMessageToConv('assistant', 'Error: ' + (err.error || 'Unknown error'), true);
      isGenerating = false;
      resetSendBtn();
      return;
    }

    if (streamMode) {
      // Stream the response
      const assistantMsg = addMessageToConv('assistant', '', false, agentMode);
      let fullText = '';
      const reader = res.body.getReader();
      const decoder = new TextDecoder();

      while (true) {
        const {done, value} = await reader.read();
        if (done) break;

        const chunk = decoder.decode(value, {stream: true});
        const lines = chunk.split('\n').filter(l => l.trim());

        for (const line of lines) {
          try {
            const data = JSON.parse(line);
            if (data.message && data.message.content) {
              fullText += data.message.content;
              assistantMsg.innerHTML = formatMarkdown(fullText);
              scrollChat();
            }
            if (data.done) break;
          } catch(e) {}
        }
      }
      conv.messages[conv.messages.length - 1].content = fullText;
    } else {
      // Non-streaming
      const data = await res.json();
      const content = data.message?.content || data.response || '';
      addMessageToConv('assistant', content, false, agentMode);
    }

    document.getElementById('msgCount').textContent = conv.messages.filter(m => m.role === 'user').length;

  } catch(e) {
    const ti = document.getElementById('typingIndicator');
    if (ti) ti.remove();
    if (e.name === 'AbortError') {
      addMessageToConv('system', 'Generation stopped.');
    } else {
      addMessageToConv('assistant', 'Connection error: ' + e.message, true);
    }
  }

  isGenerating = false;
  abortController = null;
  resetSendBtn();
  saveConversations();
  input.focus();
}

function stopGeneration() {
  if (abortController) {
    abortController.abort();
  }
}

function resetSendBtn() {
  const sendBtn = document.getElementById('sendBtn');
  sendBtn.textContent = 'Send';
  sendBtn.className = 'send-btn';
  sendBtn.onclick = sendMessage;
}

function addMessageToConv(role, content, isError, isAgent) {
  const conv = getActiveConv();
  if (!conv) return null;

  if (role !== 'system') {
    conv.messages.push({role: role, content: content, agent: isAgent});
  }

  const container = document.getElementById('chatContainer');
  const div = document.createElement('div');
  let cls = role;
  if (isError) cls = 'error';
  else if (isAgent && role === 'assistant') cls = 'agent';
  else if (role === 'system') cls = 'system';
  div.className = 'message ' + cls;
  div.innerHTML = `<div class="msg-actions"><button class="msg-action-btn" onclick="copyMessage(this)" title="Copy">&#128203;</button></div>` + formatMarkdown(content);
  container.appendChild(div);
  scrollChat();
  return div;
}

// ── UI TOGGLES ───────────────────────────────────────────────
function toggleSidebar() {
  document.getElementById('sidebar').classList.toggle('collapsed');
}

function toggleSettings() {
  document.getElementById('settingsPanel').classList.toggle('open');
}

function toggleSearch() {
  const bar = document.getElementById('searchBar');
  bar.classList.toggle('open');
  if (bar.classList.contains('open')) {
    document.getElementById('chatSearchInput').focus();
  }
}

function toggleAgent() {
  const toggle = document.getElementById('agentToggle');
  agentMode = !agentMode;
  toggle.classList.toggle('on', agentMode);
  document.getElementById('agentIndicator').style.display = agentMode ? 'inline' : 'none';
  const conv = getActiveConv();
  if (conv) conv.agentMode = agentMode;
  saveConversations();
}

function updateAgentUI() {
  const toggle = document.getElementById('agentToggle');
  toggle.classList.toggle('on', agentMode);
  document.getElementById('agentIndicator').style.display = agentMode ? 'inline' : 'none';
}

function toggleStream() {
  const toggle = document.getElementById('streamToggle');
  streamMode = !streamMode;
  toggle.classList.toggle('on', streamMode);
}

function switchModel(model) {
  currentModel = model;
  updateModelBadge();
  const conv = getActiveConv();
  if (conv) conv.model = model;
  saveConversations();
}

function updateModelBadge() {
  const badge = document.getElementById('modelBadge');
  const info = {
    gemma4: {family: 'Gemma 4', color: '#8b5cf6'},
    gemma3n: {family: 'Gemma 3n', color: '#f59e0b'},
    gemma3: {family: 'Gemma 3', color: '#238636'},
    gemma2: {family: 'Gemma 2', color: '#1f6feb'},
    codegemma: {family: 'CodeGemma', color: '#da3633'},
    shieldgemma: {family: 'ShieldGemma', color: '#6e40c9'},
    gemma: {family: 'Gemma', color: '#6e7681'}
  };
  let found = null;
  for (const [key, val] of Object.entries(info)) {
    if (currentModel.startsWith(key)) { found = val; break; }
  }
  if (found) {
    badge.style.background = found.color;
    badge.textContent = found.family + ' \u2022 ' + currentModel;
  } else {
    badge.textContent = currentModel;
  }
  document.getElementById('modelName').textContent = badge.textContent;
}

// ── SEARCH ───────────────────────────────────────────────────
function searchChat() {
  const query = document.getElementById('chatSearchInput').value.toLowerCase();
  const conv = getActiveConv();
  if (!query || !conv) {
    clearHighlights();
    document.getElementById('searchCount').textContent = '';
    return;
  }
  let count = 0;
  const messages = document.querySelectorAll('#chatContainer .message');
  messages.forEach(msg => {
    const text = msg.textContent.toLowerCase();
    if (text.includes(query)) {
      count++;
      msg.style.outline = '2px solid var(--amber)';
      msg.style.outlineOffset = '2px';
    } else {
      msg.style.outline = 'none';
    }
  });
  document.getElementById('searchCount').textContent = count + ' found';
}

function clearSearch() {
  document.getElementById('chatSearchInput').value = '';
  clearHighlights();
  document.getElementById('searchCount').textContent = '';
}

function clearHighlights() {
  document.querySelectorAll('#chatContainer .message').forEach(msg => {
    msg.style.outline = 'none';
  });
}

// ── EXPORT ───────────────────────────────────────────────────
function exportChat() {
  const conv = getActiveConv();
  if (!conv) return;
  const data = {
    title: conv.title,
    model: conv.model,
    systemPrompt: conv.systemPrompt,
    temperature: conv.temperature,
    agentMode: conv.agentMode,
    messages: conv.messages,
    exportedAt: new Date().toISOString()
  };
  const blob = new Blob([JSON.stringify(data, null, 2)], {type: 'application/json'});
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `chat-${conv.title.replace(/[^a-z0-9]/gi, '_')}-${Date.now()}.json`;
  a.click();
  URL.revokeObjectURL(url);
}

// ── COPY MESSAGE ─────────────────────────────────────────────
function copyMessage(btn) {
  const msg = btn.closest('.message');
  const text = msg.textContent.replace(/\u{1F4CB}/u, '').trim();
  navigator.clipboard.writeText(text).then(() => {
    btn.textContent = '\u2713';
    setTimeout(() => btn.textContent = '\u{1F4CB}', 1500);
  });
}

// ── FORMATTING ───────────────────────────────────────────────
function formatMarkdown(text) {
  text = text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  text = text.replace(/```(\w*)\n?([\s\S]*?)```/g, '<pre><code>$2</code></pre>');
  text = text.replace(/`([^`]+)`/g, '<code>$1</code>');
  text = text.replace(/\*\*(.+?)\*\*/g, '<b>$1</b>');
  text = text.replace(/\*(.+?)\*/g, '<i>$1</i>');
  text = text.replace(/\n/g, '<br>');
  return text;
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

function scrollChat() {
  const c = document.getElementById('chatContainer');
  c.scrollTop = c.scrollHeight;
}
</script>
</body>
</html>"""


# ── BACKEND HANDLERS ──────────────────────────────────────────

async def proxy_to_ollama(path, request):
    """Proxy requests to Ollama API"""
    import aiohttp
    url = f"http://{OLLAMA_HOST}:{OLLAMA_PORT}{path}"
    try:
        async with aiohttp.ClientSession() as session:
            async with session.request(
                request.method, url,
                headers={'Content-Type': 'application/json'},
                data=await request.read(),
                timeout=aiohttp.ClientTimeout(total=300)
            ) as resp:
                return web.Response(
                    status=resp.status,
                    body=await resp.read(),
                    content_type='application/json'
                )
    except Exception as e:
        return web.json_response({'error': str(e)}, status=502)


def verify_token(request):
    """Verify the auth token from the request"""
    auth = request.headers.get('Authorization', '')
    if auth.startswith('Bearer '):
        token = auth[7:]
        return active_sessions.get(token) is not None
    return False


async def handle_index(request):
    """Serve the chat UI"""
    html = HTML_PAGE.replace('__MODEL__', MODEL)
    html = html.replace('__HAS_PASSWORD__', 'true' if PASSWORD else 'false')
    return web.Response(text=html, content_type='text/html')


async def handle_auth(request):
    """Handle login/authentication"""
    try:
        data = await request.json()
        password = data.get('password', '')

        if PASSWORD and password != PASSWORD:
            return web.json_response({'ok': False, 'error': 'Invalid password'})

        token = hashlib.sha256(f"{time.time()}{os.urandom(16).hex()}".encode()).hexdigest()
        active_sessions[token] = {'created': time.time(), 'model': MODEL}

        return web.json_response({'ok': True, 'token': token})
    except Exception as e:
        return web.json_response({'ok': False, 'error': str(e)})


async def handle_status(request):
    """Check Ollama server status"""
    import aiohttp
    ollama_running = False
    model_info = MODEL
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(f"http://{OLLAMA_HOST}:{OLLAMA_PORT}/api/tags",
                                   timeout=aiohttp.ClientTimeout(total=5)) as resp:
                if resp.status == 200:
                    ollama_running = True
                    data = await resp.json()
                    models = data.get('models', [])
                    for m in models:
                        if MODEL in m.get('name', ''):
                            model_info = m.get('name', MODEL)
                            break
    except:
        pass

    return web.json_response({
        'ollama_running': ollama_running,
        'model': model_info,
        'server': 'Free-GHA-VPS AI Chat'
    })


async def handle_models(request):
    """Return available Gemma models"""
    return web.json_response(GEMMA_MODELS)


async def handle_chat(request):
    """Handle chat messages with streaming"""
    if not verify_token(request):
        return web.json_response({'error': 'Unauthorized'}, status=401)

    try:
        data = await request.json()
        chat_messages = data.get('messages', [])
        model = data.get('model', MODEL)
        stream = data.get('stream', True)
        options = data.get('options', {})

        # Save chat to history
        if chat_messages:
            history_file = os.path.join(CHAT_HISTORY_DIR, f"chat-{int(time.time())}.json")
            with open(history_file, 'w') as f:
                json.dump({'model': model, 'messages': chat_messages,
                          'timestamp': time.time(), 'options': options}, f)

        # Proxy to Ollama with streaming
        import aiohttp
        ollama_url = f"http://{OLLAMA_HOST}:{OLLAMA_PORT}/api/chat"

        ollama_payload = {'model': model, 'messages': chat_messages, 'stream': stream}
        if options:
            ollama_payload['options'] = options

        if not stream:
            # Non-streaming: just proxy the response
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    ollama_url, json=ollama_payload,
                    timeout=aiohttp.ClientTimeout(total=300)
                ) as resp:
                    body = await resp.read()
                    return web.Response(status=resp.status, body=body,
                                       content_type='application/json')

        # Streaming response
        response = web.StreamResponse(
            status=200,
            headers={'Content-Type': 'text/event-stream',
                     'Cache-Control': 'no-cache',
                     'Connection': 'keep-alive'}
        )
        await response.prepare(request)

        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    ollama_url, json=ollama_payload,
                    timeout=aiohttp.ClientTimeout(total=300)
                ) as resp:
                    async for line in resp.content:
                        await response.write(line)
        except Exception as e:
            error_msg = json.dumps({'error': str(e)}).encode()
            await response.write(error_msg)

        await response.write_eof()
        return response

    except Exception as e:
        return web.json_response({'error': str(e)}, status=500)


async def handle_api_proxy(request):
    """Proxy Ollama API requests"""
    if not verify_token(request):
        return web.json_response({'error': 'Unauthorized'}, status=401)
    return await proxy_to_ollama('/api' + request.path_info, request)


async def handle_api_generate(request):
    """Proxy generate endpoint"""
    if not verify_token(request):
        return web.json_response({'error': 'Unauthorized'}, status=401)
    return await proxy_to_ollama('/api/generate', request)


async def handle_api_tags(request):
    """Proxy tags endpoint"""
    return await proxy_to_ollama('/api/tags', request)


def create_app():
    app = web.Application()
    app.router.add_get('/', handle_index)
    app.router.add_post('/auth', handle_auth)
    app.router.add_get('/status', handle_status)
    app.router.add_get('/models', handle_models)
    app.router.add_post('/chat', handle_chat)
    app.router.add_post('/api/generate', handle_api_generate)
    app.router.add_get('/api/tags', handle_api_tags)
    app.router.add_route('*', '/api/{path:.*}', handle_api_proxy)
    return app


if __name__ == '__main__':
    print(f"Starting AI Chat UI on port {CHAT_PORT}")
    print(f"   Model: {MODEL}")
    print(f"   Ollama: http://{OLLAMA_HOST}:{OLLAMA_PORT}")
    print(f"   Password: {'***' if PASSWORD else '(none)'}")

    app = create_app()
    web.run_app(app, host='0.0.0.0', port=CHAT_PORT, print=None)
PYEOF

echo "   ✅ Chat UI script created"

# ── Start the chat UI server ─────────────────────────────────
echo "🌐 Starting chat UI server on port $CHAT_PORT..."

export AI_PASSWORD="$AI_PASS"
export AI_MODEL="$MODEL"
export CHAT_PORT="$CHAT_PORT"
export OLLAMA_PORT="$OLLAMA_PORT"
export OLLAMA_HOST="localhost"
export CHAT_HISTORY_DIR="/home/runner/ai-data/history"

nohup python3 /home/runner/ai-data/chat-server.py > /tmp/ai-chat-server.log 2>&1 &
CHAT_PID=$!
sleep 3

if ! kill -0 $CHAT_PID 2>/dev/null; then
  echo "❌ Chat UI server failed to start!"
  cat /tmp/ai-chat-server.log
  exit 1
fi
echo "   ✅ Chat UI running (PID: $CHAT_PID, port: $CHAT_PORT)"

# ── Verify everything is responding ─────────────────────────
echo "🔍 Verifying services..."

# Check Ollama
OLLAMA_OK=false
for i in $(seq 1 15); do
  if curl -sf http://localhost:$OLLAMA_PORT/api/tags > /dev/null 2>&1; then
    OLLAMA_OK=true
    break
  fi
  sleep 1
done

if [ "$OLLAMA_OK" = true ]; then
  echo "   ✅ Ollama API is responding"
else
  echo "   ⚠️  Ollama API not responding yet (may need more time)"
fi

# Check Chat UI
CHAT_OK=false
for i in $(seq 1 10); do
  if curl -sf http://localhost:$CHAT_PORT > /dev/null 2>&1; then
    CHAT_OK=true
    break
  fi
  sleep 1
done

if [ "$CHAT_OK" = true ]; then
  echo "   ✅ Chat UI is responding"
else
  echo "   ⚠️  Chat UI not responding yet"
fi

# ── Save PIDs for keepalive ──────────────────────────────────
echo "OLLAMA_PID=$OLLAMA_PID" >> "${GITHUB_ENV:-/dev/null}"
echo "CHAT_PID=$CHAT_PID" >> "${GITHUB_ENV:-/dev/null}"
echo "AI_MODEL=$MODEL" >> "${GITHUB_ENV:-/dev/null}"

echo ""
echo "✅ AI model server is ready!"
echo "   🤖 Model:   $MODEL"
echo "   🔌 Ollama:  http://localhost:$OLLAMA_PORT"
echo "   🌐 Chat UI: http://localhost:$CHAT_PORT"
echo "   🔑 Password: $AI_PASS"
