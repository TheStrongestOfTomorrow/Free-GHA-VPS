<div align="center">

# 🖥️ Free GHA VPS

**Get a free VPS, code editor, web host, or AI model — fork, run, connect. That's it.**

[![GitHub Actions](https://img.shields.io/badge/GitHub-Actions-2088FF?logo=github&logoColor=white)](https://github.com/features/actions)
[![Storage](https://img.shields.io/badge/Storage-Up%20to%2015GB-34A853?logo=googledrive&logoColor=white)](#-storage)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![4 Workflows](https://img.shields.io/badge/Workflows-4-purple)](#-workflows)

🖥️ **Remote Desktop** · 💻 **Code Editor** · 🌐 **Web Hosting** · 🤖 **AI Models** · 📨 **Notifications** · 💾 **Up to 15GB** · ⚡ **Cached installs**

</div>

---

## 🎯 What Is This?

Free GHA VPS gives you **4 free services** powered by GitHub Actions runners:

| Service | Description | Data Saved To |
|---------|-------------|---------------|
| 🖥️ **Free GHA VPS** | Full remote desktop (XFCE4) with 5 connection methods | `vps-data` branch |
| 💻 **Code-Server** | Browser-based VS Code for coding on the go | `code-server-data` branch |
| 🌐 **Free Web Host** | Host any website/app with auto-detected framework | `web-data` branch |
| 🤖 **AI Model (Gemma)** | Run Google Gemma models with browser chat UI | `ai-data` branch |

All four share: 30-min sessions, extendable up to 3 hours, Discord + Telegram notifications, smart caching, and persistent storage.

---

## 🚀 Quick Start (Any Workflow)

### Step 1: Fork This Repo

Hit the **Fork** button at the top.

### Step 2: Run a Workflow

1. Go to your fork → **Actions** tab
2. Pick a workflow → **Run workflow**
3. Fill in the inputs → Click **Run**
4. Wait for the URL/info in the logs → Connect!

### Step 3: Connect! 🎉

A URL or connection info appears in the workflow logs. Click it — you're in!

---

## 🖥️ Free GHA VPS (Remote Desktop)

Full XFCE4 desktop with 5 ways to connect:

| Method | Account Needed? | Quality | Speed | Setup |
|--------|:-:|:-:|:-:|:-:|
| **☁️ Cloudflare noVNC** (default) | None | Good | Fast | Zero |
| **🌐 localhost.run noVNC** | None | Good | Medium | Zero |
| **🔗 Chrome Remote Desktop** | Google | Best | Fast | Auth code |
| **🦎 Tailscale + xRDP** | Tailscale | Best | Fastest | Auth key |

### How to Run

1. Actions → **🖥️ Free GHA VPS** → Run workflow
2. **PIN** — any 6+ character password (letters/numbers, or leave blank for auto)
3. **connection** — pick a method (see table above)
4. **resolution** — `1920x1080` / `1280x720` / `2560x1440`
5. **storage** — leave at `auto`
6. **duration** — leave at `30`

### ☁️ Cloudflare noVNC (Recommended — Zero Setup)

No account, no secrets, nothing. Just run and click the URL.

1. Set `connection` = `auto` or `novnc-cloudflare`
2. Run → URL appears: `https://xxx.trycloudflare.com/vnc.html`
3. Click → enter password → **you're in!**

### 🔗 Chrome Remote Desktop (Best Quality)

One-time auth setup, then it remembers you forever.

1. Set `connection` = `chrome-remote-desktop`
2. **First time:** Open [remotedesktop.google.com/headless](https://remotedesktop.google.com/headless) → Sign in → Copy the `--code` value → Paste in `auth_code` field
3. **After that:** Just enter your PIN and run!

### 🦎 Tailscale + xRDP (Real RDP Protocol)

1. Sign up at [tailscale.com](https://tailscale.com) (free)
2. Settings → Keys → Generate auth key (Reusable + Ephemeral)
3. Add as GitHub secret: `TS_AUTHKEY`
4. Set `connection` = `xrdp-tailscale` → Run → Connect with any RDP client!

---

## 💻 Code-Server (Browser VS Code)

Lightweight coding environment — no desktop overhead, starts fast.

### How to Run

1. Actions → **💻 Code-Server** → Run workflow
2. **password** — your code-server password (min 6 chars, or leave blank for auto)
3. **tunnel** — `cloudflare` (default) or `localhost`
4. **clone_repo** — (optional) paste a GitHub repo URL to auto-clone
5. **duration** — leave at `30`

### What You Get

- Full VS Code in your browser
- Terminal, extensions, Git integration
- Workspace at `/home/runner/workspace`
- Auto-saves all files and settings between sessions
- Optional: auto-clone your repo on startup

### Connect

A Cloudflare/localhost URL appears in the logs. Open it → enter password → code!

---

## 🌐 Free Web Host

Host any website or web app publicly via a Cloudflare tunnel.

### How to Run

1. Actions → **🌐 Free Web Host** → Run workflow
2. **repo_url** — paste a GitHub repo URL to host (or leave blank for restored files)
3. **build_command** — `auto` (auto-detect) or custom (e.g. `npm run build`)
4. **server** — `auto` / `nginx` / `node` / `python`
5. **port** — `8080` (default)
6. **tunnel** — `cloudflare` (default) or `localhost`
7. **duration** — leave at `30`

### Auto-Detection

The system automatically detects your framework:

| Detected | Framework | Server |
|----------|-----------|--------|
| `package.json` with build script | React, Next.js, Vite, etc. | Node (serve) |
| `package.json` with start script | Express, etc. | Node (npm start) |
| `requirements.txt` / `app.py` | Flask | Python |
| `manage.py` | Django | Python |
| No framework files | Static HTML/CSS/JS | Nginx |

### Connect

A public HTTPS URL appears in the logs. Share it, point a domain to it, or use it directly. Cloudflare tunnels provide **automatic HTTPS** — no SSL setup needed!

---

## 🤖 AI Model (Google Gemma)

Run Google Gemma AI models directly in your browser with a beautiful chat interface. Powered by Ollama inference engine.

### Supported Models

| Model | Parameters | Download Size | Speed | Best For |
|-------|:----------:|:-------------:|:-----:|----------|
| **gemma3:1b** | 1B | ~800MB | ⚡⚡⚡ | Quick answers, lightweight tasks |
| **gemma3:4b** | 4B | ~2.6GB | ⚡⚡ | Good balance of quality and speed |
| **gemma2:2b** | 2B | ~1.5GB | ⚡⚡⚡ | Fast responses, decent quality |
| **gemma2:9b** | 9B | ~5.3GB | ⚡ | Best quality (may be slow) |
| **gemma:2b** | 2B | ~1.4GB | ⚡⚡⚡ | Original Gemma, fast |
| **gemma:7b** | 7B | ~4.7GB | ⚡ | Original Gemma, quality |

### How to Run

1. Actions → **🤖 AI Model (Gemma)** → Run workflow
2. **model** — pick a Gemma model (default: `gemma3:1b`)
3. **password** — your chat UI password (min 6 chars, or leave blank for auto)
4. **tunnel** — `cloudflare` (default) or `localhost`
5. **duration** — leave at `30`

### Connect

A URL appears in the workflow logs. Open it → enter password → start chatting!

### Features

- 🌐 **Browser Chat UI** — Beautiful dark theme, Markdown rendering, streaming responses
- 🔌 **Ollama API** — Full Ollama-compatible API for programmatic access
- 💬 **Chat History** — Conversations saved between sessions
- 🔒 **Password Protected** — Your AI instance is private
- ⚡ **Streaming** — See responses in real-time as they generate
- 📊 **Inference Stats** — Monitor tokens/sec and model performance

### API Access

The AI model server exposes an Ollama-compatible API. Example:

```bash
# Generate text
curl https://your-url.trycloudflare.com/api/generate \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"model":"gemma3:1b","prompt":"Explain quantum computing"}'

# Chat completion
curl https://your-url.trycloudflare.com/api/chat \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"model":"gemma3:1b","messages":[{"role":"user","content":"Hello!"}]}'
```

---

All 4 workflows support session extension (up to 3 hours total):

1. Actions → **⏰ Extend Session** → Run
2. Default: +30 minutes per extension (max 5 extensions)
3. Works for VPS, Code-Server, Web Host, AND AI Model — the extend signal is universal!

---

## 📨 Notifications (Discord + Telegram)

Get alerts on your phone/desktop when events happen — **zero dependencies, pure open APIs**.

### Setup Discord

1. Open your Discord server → Server Settings → Integrations → Webhooks
2. Create a webhook → Copy the URL
3. Add as GitHub secret: `DISCORD_WEBHOOK_URL`
4. Done! You'll get notifications for: start, ready, error, end, extend

### Setup Telegram

1. Message [@BotFather](https://t.me/BotFather) on Telegram → `/newbot` → Get your **bot token**
2. Message your bot to start a chat → Visit `https://api.telegram.org/bot<TOKEN>/getUpdates` → Find your **chat_id**
3. Add as GitHub secrets:
   - `TELEGRAM_BOT_TOKEN` — your bot token
   - `TELEGRAM_CHAT_ID` — your chat ID
4. Done!

### What You'll Get Notified About

| Event | Discord | Telegram |
|-------|:-:|:-:|
| 🚀 Session starting | ✅ | ✅ |
| ✅ Ready / URL available | ✅ | ✅ |
| ⏰ Session extended | ✅ | ✅ |
| 👋 Session ended | ✅ | ✅ |
| ❌ Errors | ✅ | ✅ |

---

## 💾 Storage

All 4 workflows auto-save data between sessions using a 3-tier system:

| Tier | Storage | Setup | Best For |
|------|---------|-------|----------|
| **Auto** (default) | ~2GB | Zero | Most users |
| **GitHub Only** | ~2GB | Zero | No Drive needed |
| **Google Drive** | 15GB | One-time | Large projects, games |

Data flow: `zstd compress → GitHub Release (2GB) → optional Google Drive (15GB)`
Restore flow: `Release → branch → Drive` (first available wins)

### Google Drive Setup (Optional)

```bash
# Install rclone
curl https://rclone.org/install.sh | sudo bash

# Configure Google Drive
rclone config  # name: "gdrive", storage: Google Drive, scope: Full access

# Get base64 config
base64 -w 0 ~/.config/rclone/rclone.conf

# Add as GitHub secret: RCLONE_CONFIG
```

Or run `bash scripts/rclone-setup.sh` locally for guided setup.

### Data Branches

Each workflow saves to its own isolated branch — no conflicts:

- 🖥️ VPS → `vps-data`
- 💻 Code-Server → `code-server-data`
- 🌐 Web Host → `web-data`
- 🤖 AI Model → `ai-data`

---

## 🔒 Concurrency Lock

Only **one instance per workflow type** can run at a time. If you try to start a second VPS while one is running, it will queue. This prevents wasted Actions minutes.

---

## ⚠️ Stay Safe

> [!WARNING]
> GitHub may suspend accounts that abuse Actions:
>
> - ✅ **30-min base sessions**
> - ✅ **Use extensions sparingly**
> - ✅ **Personal accounts only**
> - ❌ **No crypto mining / automation loops / illegal use**

---

## ❓ Troubleshooting

### "noVNC URL not showing"
Wait 30 sec. Check the logs for the tunnel URL. If Cloudflare fails, try `novnc-localhost`.

### "Tunnel URL doesn't load"
Cloudflare quick tunnels can be slow in some regions. Try `novnc-localhost` or CRD/Tailscale.

### "CRD not connecting"
Complete the auth code step for first setup. Use the same PIN. Check workflow logs.

### "Tailscale IP not showing"
Verify your `TS_AUTHKEY` secret is valid and not expired. Generate a new key.

### "Data not persisting"
Check if the data branch exists. For Drive: verify `RCLONE_CONFIG` secret.

### "Notifications not working"
Verify secrets are set correctly. Discord: check webhook URL. Telegram: verify token + chat ID by visiting `https://api.telegram.org/bot<TOKEN>/getMe`

### "AI model not responding"
The first inference request may be slow as the model loads into memory. Try a smaller model like `gemma3:1b`. Check Ollama logs in the workflow output.

### "AI model download fails"
Larger models need more disk space. Try `gemma3:1b` (~800MB). Check your storage isn't full from previous sessions.

### "Chat UI shows 'Offline'"
The Ollama server may need a moment to start. Wait 30 seconds and refresh. If still offline, check the workflow logs for errors.

---

## 📁 Repo Structure

```
Free-GHA-VPS/
├── .github/workflows/
│   ├── vps.yml              # 🖥️ Remote desktop (5 connection methods)
│   ├── code-server.yml      # 💻 Browser VS Code
│   ├── web-host.yml         # 🌐 Web hosting
│   ├── ai-model.yml         # 🤖 AI model inference (Gemma)
│   └── extend.yml           # ⏰ Session extender (works for all 4)
├── scripts/
│   ├── setup.sh             # VPS environment installer (cached)
│   ├── configure-crd.sh     # Chrome Remote Desktop PIN + auth
│   ├── start-desktop.sh     # Xvfb + XFCE4
│   ├── setup-novnc.sh       # x11vnc + noVNC + websockify
│   ├── start-novnc.sh       # Launch VNC + noVNC
│   ├── tunnel-cloudflare.sh # Cloudflare quick tunnel
│   ├── tunnel-localhost.sh  # localhost.run tunnel
│   ├── setup-xrdp.sh        # xRDP server
│   ├── setup-tailscale.sh   # Tailscale VPN
│   ├── setup-codeserver.sh  # Code-server installer (cached)
│   ├── start-codeserver.sh  # Launch code-server
│   ├── keepalive-codeserver.sh  # Code-server keepalive + extension
│   ├── save-codeserver-data.sh  # Save code-server workspace
│   ├── setup-webhost.sh     # Web host installer (cached)
│   ├── start-webhost.sh     # Auto-detect + start web server
│   ├── save-webhost-data.sh # Save web files
│   ├── setup-ai-model.sh    # AI model installer (Ollama + Gemma)
│   ├── start-ai-model.sh    # Launch AI model + chat UI
│   ├── keepalive-ai.sh       # AI model keepalive + monitoring
│   ├── save-ai-data.sh       # Save AI chat history + config
│   ├── restore-data.sh      # Restore: Release → branch → Drive
│   ├── save-data.sh         # Save: zstd → Release → Drive
│   ├── keepalive.sh         # VPS timer + extension + auto-restart
│   ├── notify.sh            # 📨 Discord + Telegram notifications
│   └── rclone-setup.sh      # Helper: Google Drive setup
├── README.md
├── LICENSE
└── .gitignore
```

---

## 🌟 All Features

| Feature | VPS | Code-Server | Web Host | AI Model |
|---------|:---:|:-----------:|:--------:|:--------:|
| 🖥️ Full Desktop | ✅ | ❌ | ❌ | ❌ |
| 💻 VS Code in Browser | ❌ | ✅ | ❌ | ❌ |
| 🌐 Public Web Hosting | ❌ | ❌ | ✅ | ❌ |
| 🤖 AI Model Inference | ❌ | ❌ | ❌ | ✅ |
| 💬 Chat UI | ❌ | ❌ | ❌ | ✅ |
| 📨 Discord Notifications | ✅ | ✅ | ✅ | ✅ |
| 📨 Telegram Notifications | ✅ | ✅ | ✅ | ✅ |
| 🗜️ zstd Compression | ✅ | ✅ | ✅ | ✅ |
| ⚡ Package Cache | ✅ | ✅ | ✅ | ✅ |
| 📤 GitHub Releases | ✅ | ✅ | ✅ | ✅ |
| ☁️ Google Drive | ✅ | ✅ | ✅ | ✅ |
| 💾 Data Persists | ✅ | ✅ | ✅ | ✅ |
| ⏰ Extendable Sessions | ✅ | ✅ | ✅ | ✅ |
| 🔒 Concurrency Lock | ✅ | ✅ | ✅ | ✅ |
| 🔄 Auto Keepalive | ✅ | ✅ | ✅ | ✅ |
| ☁️ Cloudflare Tunnel | ✅ | ✅ | ✅ | ✅ |
| 📐 Resizable | ✅ | ❌ | ❌ | ❌ |
| 🚀 Zero Cost | ✅ | ✅ | ✅ | ✅ |

---

## 📜 License

MIT — use at your own risk. Educational/personal use only.

---

<div align="center">

**Powered by [GitHub Actions](https://github.com/features/actions)**

⭐ Star if this helped you!

</div>
