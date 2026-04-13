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
pkill -f ollama 2>/dev/null || true
pkill -f "python3.*ai-chat" 2>/dev/null || true
sleep 2

# ── Start Ollama server ─────────────────────────────────────
echo "🤖 Starting Ollama inference server..."
export OLLAMA_HOST="0.0.0.0:$OLLAMA_PORT"
export OLLAMA_MODELS="/home/runner/.ollama/models"
nohup ollama serve > /tmp/ollama-server.log 2>&1 &
OLLAMA_PID=$!
sleep 5

if ! kill -0 $OLLAMA_PID 2>/dev/null; then
  echo "❌ Ollama failed to start!"
  cat /tmp/ollama-server.log
  exit 1
fi
echo "   ✅ Ollama running (PID: $OLLAMA_PID, port: $OLLAMA_PORT)"

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
AI Chat UI Server - Browser-based interface for Ollama/Gemma models
Serves a chat UI and proxies requests to Ollama API
"""
import asyncio
import json
import os
import time
import hashlib
import base64
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

HTML_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>🤖 AI Chat - Gemma</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
       background: #0d1117; color: #c9d1d9; height: 100vh; display: flex; flex-direction: column; }
.header { background: #161b22; padding: 12px 20px; border-bottom: 1px solid #30363d;
          display: flex; align-items: center; gap: 12px; flex-shrink: 0; }
.header h1 { font-size: 18px; color: #58a6ff; }
.header .model-badge { background: #238636; color: #fff; padding: 3px 10px;
                       border-radius: 12px; font-size: 12px; font-weight: 600; }
.header .status { margin-left: auto; font-size: 12px; color: #8b949e; }
.header .status.online { color: #3fb950; }
.header .status.offline { color: #f85149; }

.chat-container { flex: 1; overflow-y: auto; padding: 20px; display: flex;
                  flex-direction: column; gap: 16px; }
.message { max-width: 85%; padding: 12px 16px; border-radius: 12px;
           line-height: 1.6; font-size: 14px; word-wrap: break-word; }
.message.user { background: #1f6feb; color: #fff; align-self: flex-end;
                border-bottom-right-radius: 4px; }
.message.assistant { background: #21262d; color: #c9d1d9; align-self: flex-start;
                     border-bottom-left-radius: 4px; }
.message.system { background: #1c2128; color: #8b949e; align-self: center;
                  font-style: italic; font-size: 13px; }
.message pre { background: #0d1117; padding: 8px 12px; border-radius: 6px;
               overflow-x: auto; margin: 8px 0; font-size: 13px; }
.message code { background: #0d1117; padding: 2px 6px; border-radius: 4px;
                font-size: 13px; }
.message.error { background: #490202; color: #f85149; }

.typing { align-self: flex-start; color: #8b949e; font-size: 13px; padding: 8px 16px; }
.typing span { animation: blink 1.4s infinite; }
.typing span:nth-child(2) { animation-delay: 0.2s; }
.typing span:nth-child(3) { animation-delay: 0.4s; }
@keyframes blink { 0%,100% { opacity: 0.2; } 50% { opacity: 1; } }

.input-area { background: #161b22; padding: 16px 20px; border-top: 1px solid #30363d;
              display: flex; gap: 12px; flex-shrink: 0; }
.input-area textarea { flex: 1; background: #0d1117; color: #c9d1d9; border: 1px solid #30363d;
                       border-radius: 8px; padding: 10px 14px; font-size: 14px;
                       font-family: inherit; resize: none; outline: none;
                       min-height: 44px; max-height: 150px; }
.input-area textarea:focus { border-color: #58a6ff; }
.input-area button { background: #238636; color: #fff; border: none; padding: 10px 20px;
                     border-radius: 8px; font-size: 14px; font-weight: 600;
                     cursor: pointer; white-space: nowrap; }
.input-area button:hover { background: #2ea043; }
.input-area button:disabled { background: #21262d; color: #484f58; cursor: not-allowed; }

.login-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0;
                 background: #0d1117; display: flex; align-items: center;
                 justify-content: center; z-index: 100; }
.login-box { background: #161b22; padding: 32px; border-radius: 12px;
             border: 1px solid #30363d; width: 360px; text-align: center; }
.login-box h2 { color: #58a6ff; margin-bottom: 8px; }
.login-box p { color: #8b949e; font-size: 13px; margin-bottom: 20px; }
.login-box input { width: 100%; background: #0d1117; color: #c9d1d9;
                   border: 1px solid #30363d; border-radius: 8px;
                   padding: 10px 14px; font-size: 14px; outline: none; margin-bottom: 12px; }
.login-box input:focus { border-color: #58a6ff; }
.login-box button { width: 100%; background: #238636; color: #fff; border: none;
                    padding: 10px; border-radius: 8px; font-size: 14px;
                    font-weight: 600; cursor: pointer; }
.login-box button:hover { background: #2ea043; }
.login-box .error { color: #f85149; font-size: 12px; margin-top: 8px; }

.info-bar { display: flex; gap: 8px; padding: 8px 20px; background: #161b22;
            border-bottom: 1px solid #30363d; font-size: 12px; color: #8b949e; }
.info-bar a { color: #58a6ff; text-decoration: none; }
.info-bar a:hover { text-decoration: underline; }

@media (max-width: 600px) {
  .message { max-width: 95%; }
  .input-area { padding: 12px; }
  .info-bar { flex-wrap: wrap; }
}
</style>
</head>
<body>

<div class="login-overlay" id="loginOverlay">
  <div class="login-box">
    <h2>🤖 AI Chat</h2>
    <p>Enter your password to access the AI chat interface</p>
    <input type="password" id="loginPass" placeholder="Password" autofocus
           onkeydown="if(event.key==='Enter')doLogin()">
    <button onclick="doLogin()">🔓 Unlock</button>
    <div class="error" id="loginError"></div>
  </div>
</div>

<div class="header">
  <h1>🤖 AI Chat</h1>
  <span class="model-badge" id="modelBadge">MODEL</span>
  <span class="status" id="status">Connecting...</span>
</div>

<div class="info-bar">
  <span>📖 Model: <strong id="modelName">-</strong></span>
  <span>⚡ API: <a href="/api" target="_blank">Ollama-compatible</a></span>
  <span>💬 Messages: <strong id="msgCount">0</strong></span>
  <span>⏱️ Session: <strong id="sessionTime">0:00</strong></span>
</div>

<div class="chat-container" id="chatContainer">
  <div class="message system">👋 Welcome! Type a message below to start chatting with the AI model. The first response may be slow as the model loads into memory.</div>
</div>

<div class="input-area">
  <textarea id="userInput" placeholder="Type your message... (Shift+Enter for new line)"
            rows="1" onkeydown="handleKeydown(event)"></textarea>
  <button id="sendBtn" onclick="sendMessage()">Send ➤</button>
</div>

<script>
const MODEL = '__MODEL__';
const OLLAMA_URL = '/api';
let sessionToken = '';
let messages = [];
let isGenerating = false;
let sessionStart = Date.now();

// Auto-resize textarea
const input = document.getElementById('userInput');
input.addEventListener('input', () => {
  input.style.height = 'auto';
  input.style.height = Math.min(input.scrollHeight, 150) + 'px';
});

function handleKeydown(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    sendMessage();
  }
}

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
  } catch(e) {
    errEl.textContent = 'Connection error';
  }
}

async function checkStatus() {
  try {
    const res = await fetch('/status', {
      headers: {'Authorization': 'Bearer ' + sessionToken}
    });
    const data = await res.json();
    const statusEl = document.getElementById('status');
    if (data.ollama_running) {
      statusEl.textContent = '● Online';
      statusEl.className = 'status online';
    } else {
      statusEl.textContent = '● Offline';
      statusEl.className = 'status offline';
    }
    document.getElementById('modelBadge').textContent = data.model || MODEL;
    document.getElementById('modelName').textContent = data.model || MODEL;
  } catch(e) {}
}

async function sendMessage() {
  const text = input.value.trim();
  if (!text || isGenerating) return;
  input.value = '';
  input.style.height = 'auto';
  isGenerating = true;
  document.getElementById('sendBtn').disabled = true;

  // Add user message
  addMessage('user', text);
  messages.push({role: 'user', content: text});

  // Show typing indicator
  const typing = document.createElement('div');
  typing.className = 'typing';
  typing.innerHTML = '🤖 Thinking<span>.</span><span>.</span><span>.</span>';
  typing.id = 'typingIndicator';
  document.getElementById('chatContainer').appendChild(typing);
  scrollChat();

  try {
    const res = await fetch('/chat', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + sessionToken
      },
      body: JSON.stringify({
        model: MODEL,
        messages: messages,
        stream: true
      })
    });

    // Remove typing indicator
    const ti = document.getElementById('typingIndicator');
    if (ti) ti.remove();

    if (!res.ok) {
      const err = await res.json().catch(() => ({error: 'Request failed'}));
      addMessage('error', '❌ ' + (err.error || 'Unknown error'));
      messages.pop(); // Remove the failed user message from history
      isGenerating = false;
      document.getElementById('sendBtn').disabled = false;
      return;
    }

    // Stream the response
    const assistantMsg = addMessage('assistant', '');
    let fullText = '';
    const reader = res.body.getReader();
    const decoder = new TextDecoder();

    while (true) {
      const {done, value} = await reader.read();
      if (done) break;

      const chunk = decoder.decode(value, {stream: true});
      const lines = chunk.split('\\n').filter(l => l.trim());

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

    messages.push({role: 'assistant', content: fullText});
    document.getElementById('msgCount').textContent = messages.length;

  } catch(e) {
    const ti = document.getElementById('typingIndicator');
    if (ti) ti.remove();
    addMessage('error', '❌ Connection error: ' + e.message);
  }

  isGenerating = false;
  document.getElementById('sendBtn').disabled = false;
  input.focus();
}

function addMessage(role, content) {
  const div = document.createElement('div');
  div.className = 'message ' + role;
  div.innerHTML = formatMarkdown(content);
  document.getElementById('chatContainer').appendChild(div);
  scrollChat();
  return div;
}

function formatMarkdown(text) {
  // Basic markdown: code blocks, inline code, bold, italic
  text = text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  // Code blocks
  text = text.replace(/```(\\w*)\\n?([\\s\\S]*?)```/g, '<pre><code>$2</code></pre>');
  // Inline code
  text = text.replace(/`([^`]+)`/g, '<code>$1</code>');
  // Bold
  text = text.replace(/\\*\\*(.+?)\\*\\*/g, '<b>$1</b>');
  // Italic
  text = text.replace(/\\*(.+?)\\*/g, '<i>$1</i>');
  // Line breaks
  text = text.replace(/\\n/g, '<br>');
  return text;
}

function scrollChat() {
  const c = document.getElementById('chatContainer');
  c.scrollTop = c.scrollHeight;
}

// Session timer
setInterval(() => {
  const elapsed = Math.floor((Date.now() - sessionStart) / 1000);
  const m = Math.floor(elapsed / 60);
  const s = elapsed % 60;
  document.getElementById('sessionTime').textContent = m + ':' + String(s).padStart(2, '0');
}, 1000);

// Check status periodically
setInterval(checkStatus, 30000);

// Init
document.getElementById('modelBadge').textContent = MODEL;
document.getElementById('modelName').textContent = MODEL;

// Color-code the model badge by family
(function() {
  const badge = document.getElementById('modelBadge');
  if (MODEL.startsWith('gemma4')) {
    badge.style.background = '#8b5cf6'; badge.textContent = 'Gemma 4 • ' + MODEL;
  } else if (MODEL.startsWith('gemma3n')) {
    badge.style.background = '#f59e0b'; badge.textContent = 'Gemma 3n • ' + MODEL;
  } else if (MODEL.startsWith('gemma3')) {
    badge.style.background = '#238636'; badge.textContent = 'Gemma 3 • ' + MODEL;
  } else if (MODEL.startsWith('gemma2')) {
    badge.style.background = '#1f6feb'; badge.textContent = 'Gemma 2 • ' + MODEL;
  } else if (MODEL.startsWith('codegemma')) {
    badge.style.background = '#da3633'; badge.textContent = 'CodeGemma • ' + MODEL;
  } else if (MODEL.startsWith('shieldgemma')) {
    badge.style.background = '#6e40c9'; badge.textContent = 'ShieldGemma • ' + MODEL;
  } else {
    badge.textContent = 'Gemma • ' + MODEL;
  }
  document.getElementById('modelName').textContent = badge.textContent;
})();

// If no password required, auto-login
if (!('__HAS_PASSWORD__' === 'true')) {
  doLoginNoPass();
} else {
  document.getElementById('loginPass').focus();
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
</script>
</body>
</html>"""


async def proxy_to_ollama(path, request):
    """Proxy requests to Ollama API"""
    import aiohttp
    url = f"http://{OLLAMA_HOST}:{OLLAMA_PORT}{path}"
    try:
        async with aiohttp.ClientSession() as session:
            async with session.request(
                request.method, url,
                headers={'Content-Type': 'application/json'},
                data=await request.read()
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

        # Generate a simple session token
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
            async with session.get(f"http://{OLLAMA_HOST}:{OLLAMA_PORT}/api/tags", timeout=aiohttp.ClientTimeout(total=5)) as resp:
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


async def handle_chat(request):
    """Handle chat messages with streaming"""
    if not verify_token(request):
        return web.json_response({'error': 'Unauthorized'}, status=401)

    try:
        data = await request.json()
        chat_messages = data.get('messages', [])
        model = data.get('model', MODEL)
        stream = data.get('stream', True)

        # Save chat to history
        if chat_messages:
            history_file = os.path.join(CHAT_HISTORY_DIR, f"chat-{int(time.time())}.json")
            with open(history_file, 'w') as f:
                json.dump({'model': model, 'messages': chat_messages, 'timestamp': time.time()}, f)

        # Proxy to Ollama with streaming
        import aiohttp
        ollama_url = f"http://{OLLAMA_HOST}:{OLLAMA_PORT}/api/chat"

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
                    ollama_url,
                    json={'model': model, 'messages': chat_messages, 'stream': stream},
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
    app.router.add_post('/chat', handle_chat)
    app.router.add_post('/api/generate', handle_api_generate)
    app.router.add_get('/api/tags', handle_api_tags)
    # Catch-all API proxy
    app.router.add_route('*', '/api/{path:.*}', handle_api_proxy)
    return app


if __name__ == '__main__':
    print(f"🌐 Starting AI Chat UI on port {CHAT_PORT}")
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
