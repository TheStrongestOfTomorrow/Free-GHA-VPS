<div align="center">

# 🖥️ Free GHA VPS

**Get a free VPS, code editor, web host, or AI model — fork, run, connect. That's it.**

[![GitHub Actions](https://img.shields.io/badge/GitHub-Actions-2088FF?logo=github&logoColor=white)](https://github.com/features/actions)
[![Storage](https://img.shields.io/badge/Storage-Up%20to%2015GB-34A853?logo=googledrive&logoColor=white)](#-storage)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![5 Workflows](https://img.shields.io/badge/Workflows-5-purple)](#-workflows)

🖥️ **Remote Desktop** · 💻 **Code Editor** · 🌐 **Web Hosting** · 🤖 **AI Models** · 🦞 **OpenClaw** · 📨 **Notifications** · 💾 **Up to 15GB** · ⚡ **Cached installs**

</div>

---

## 🎯 What Is This?

Free GHA VPS gives you **5 free services** powered by GitHub Actions runners:

| Service | Description | Data Saved To |
|---------|-------------|---------------|
| 🖥️ **Free GHA VPS** | Full remote desktop (XFCE4) with 5 connection methods | `vps-data` branch |
| 💻 **Code-Server** | Browser-based VS Code with AI CLI tools | `code-server-data` branch |
| 🌐 **Free Web Host** | Host any website/app with auto-detected framework | `web-data` branch |
| 🤖 **AI Model (Gemma)** | Run Google Gemma models with browser chat UI | `ai-data` branch |
| 🦞 **OpenClaw** | Run ANY Ollama model (Llama, Mistral, Phi, Gemma, etc.) | `openclaw-data` branch |

All five share: 30-min sessions, extendable up to 3 hours, Discord + Telegram notifications, smart caching, and persistent storage.

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

---

## 💻 Code-Server (Browser VS Code)

Lightweight coding environment — no desktop overhead, starts fast. Now with **AI CLI tools** pre-installed!

### How to Run

1. Actions → **💻 Code-Server** → Run workflow
2. **password** — your code-server password (min 6 chars, or leave blank for auto)
3. **tunnel** — `cloudflare` (default) or `localhost`
4. **clone_repo** — (optional) paste a GitHub repo URL to auto-clone
5. **install_ai_tools** — `true` (default) to install Gemini CLI, Claude Code/OpenCode, Codex CLI + AI extensions
6. **duration** — leave at `30`

### AI CLI Tools (New!)

When `install_ai_tools` is enabled (default), the following are installed:

| Tool | Description | Command | API Key Env |
|------|-------------|---------|-------------|
| **Gemini CLI** | Google's AI assistant | `gemini` or `./gemini-chat.sh` | `GEMINI_API_KEY` |
| **Claude Code** | Anthropic's AI coding assistant | `claude` or `./claude-code.sh` | `ANTHROPIC_API_KEY` |
| **OpenCode** | Open-source Claude Code alternative | `opencode` | `ANTHROPIC_API_KEY` |
| **Codex CLI** | OpenAI's code generation tool | `codex` or `./codex-cli.sh` | `OPENAI_API_KEY` |

### AI Code-Server Extensions

These AI-powered VS Code extensions are installed automatically:

- **Continue** — Open-source AI code assistant (works with any LLM)
- **Roo Code** — AI-powered autonomous coding agent
- **Cline** — AI dev assistant
- **Gemini Code Assist** — Google's code assistant
- **CodeGPT** — GPT integration for VS Code

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

---

## 🤖 AI Model (Google Gemma)

Run Google Gemma AI models directly in your browser with a beautiful chat interface. Powered by Ollama inference engine.

### How to Run

1. Actions → **🤖 AI Model (Gemma)** → Run workflow
2. **model** — pick a Gemma model (default: `gemma3:1b`)
3. **password** — your chat UI password (min 6 chars, or leave blank for auto)
4. **tunnel** — `cloudflare` (default) or `localhost`
5. **duration** — leave at `30`

---

## 🦞 OpenClaw (NEW — Any Ollama Model)

Run **any** Ollama model — not just Gemma! Choose from Ollama's entire model library or select a Gemma model. Perfect for Llama, Mistral, Phi, DeepSeek, Qwen, and more.

### How to Run

1. Actions → **🦞 OpenClaw** → Run workflow
2. **model_source** — `gemma` (select from list) or `ollama-custom` (type any model name)
3. **ollama_model** — (only if source=ollama-custom) Type any Ollama model name (e.g. `llama3.2`, `mistral`, `phi4`, `deepseek-r1:7b`)
4. **gemma_model** — (only if source=gemma) Pick from the Gemma dropdown
5. **password** — your chat UI password (min 6 chars, or leave blank for auto)
6. **tunnel** — `cloudflare` (default) or `localhost`
7. **install_ai_tools** — (optional) Install AI CLI tools alongside the model
8. **duration** — leave at `30`

### Popular Ollama Models

| Model | Parameters | Download | Best For |
|-------|:----------:|:--------:|----------|
| **llama3.2** | 3B | ~2GB | General chat, fast |
| **llama3.1:8b** | 8B | ~4.7GB | High quality chat |
| **mistral** | 7B | ~4.1GB | Balanced performance |
| **phi4** | 14B | ~9GB | Reasoning tasks |
| **deepseek-r1:7b** | 7B | ~4.7GB | Chain-of-thought reasoning |
| **qwen2.5-coder** | 7B | ~4.4GB | Code generation |
| **codellama** | 7B | ~3.8GB | Code completion |
| **tinyllama** | 1.1B | ~637MB | Ultra-fast, lightweight |
| **gemma3:1b** | 1B | ~815MB | Fast Gemma, recommended |

### Connect

A URL appears in the workflow logs. Open it → enter password → start chatting with any model!

---

All 5 workflows support session extension (up to 3 hours total):

1. Actions → **⏰ Extend Session** → Run
2. Default: +30 minutes per extension (max 5 extensions)
3. Works for VPS, Code-Server, Web Host, AI Model, AND OpenClaw — the extend signal is universal!

---

## 📨 Notifications (Discord + Telegram)

Get alerts on your phone/desktop when events happen — **zero dependencies, pure open APIs**.

### Setup Discord

1. Open your Discord server → Server Settings → Integrations → Webhooks
2. Create a webhook → Copy the URL
3. Add as GitHub secret: `DISCORD_WEBHOOK_URL`

### Setup Telegram

1. Message [@BotFather](https://t.me/BotFather) → `/newbot` → Get your **bot token**
2. Message your bot → Visit `https://api.telegram.org/bot<TOKEN>/getUpdates` → Find your **chat_id**
3. Add as GitHub secrets: `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`

---

## 💾 Storage

All 5 workflows auto-save data between sessions using a 3-tier system:

| Tier | Storage | Setup | Best For |
|------|---------|-------|----------|
| **Auto** (default) | ~2GB | Zero | Most users |
| **GitHub Only** | ~2GB | Zero | No Drive needed |
| **Google Drive** | 15GB | One-time | Large projects, games |

### Data Branches

- 🖥️ VPS → `vps-data`
- 💻 Code-Server → `code-server-data`
- 🌐 Web Host → `web-data`
- 🤖 AI Model → `ai-data`
- 🦞 OpenClaw → `openclaw-data`

---

## 🔒 Concurrency Lock

Only **one instance per workflow type** can run at a time.

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

## 📁 Repo Structure

```
Free-GHA-VPS/
├── .github/workflows/
│   ├── vps.yml              # 🖥️ Remote desktop (5 connection methods)
│   ├── code-server.yml      # 💻 Browser VS Code + AI CLI tools
│   ├── web-host.yml         # 🌐 Web hosting
│   ├── ai-model.yml         # 🤖 AI model inference (Gemma)
│   ├── openclaw.yml         # 🦞 Any Ollama model (Llama, Mistral, etc.)
│   ├── extend.yml           # ⏰ Session extender (works for all 5)
│   └── stop.yml             # 🛑 Stop any running session
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
│   ├── setup-codeserver.sh  # Code-server installer + base extensions (cached)
│   ├── start-codeserver.sh  # Launch code-server
│   ├── setup-ai-cli-tools.sh # AI CLI tools (Gemini, Claude, Codex)
│   ├── keepalive-codeserver.sh  # Code-server keepalive + extension
│   ├── save-codeserver-data.sh  # Save code-server workspace
│   ├── setup-webhost.sh     # Web host installer (cached)
│   ├── start-webhost.sh     # Auto-detect + start web server
│   ├── save-webhost-data.sh # Save web files
│   ├── setup-ai-model.sh    # AI model installer (Ollama + Gemma)
│   ├── start-ai-model.sh    # Launch AI model + chat UI
│   ├── keepalive-ai.sh       # AI model keepalive + monitoring
│   ├── save-ai-data.sh       # Save AI chat history + config
│   ├── setup-openclaw.sh     # OpenClaw installer (any Ollama model)
│   ├── start-openclaw.sh     # Launch OpenClaw + chat UI (any model)
│   ├── save-openclaw-data.sh # Save OpenClaw data
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

| Feature | VPS | Code-Server | Web Host | AI Model | OpenClaw |
|---------|:---:|:-----------:|:--------:|:--------:|:--------:|
| 🖥️ Full Desktop | ✅ | ❌ | ❌ | ❌ | ❌ |
| 💻 VS Code in Browser | ❌ | ✅ | ❌ | ❌ | ❌ |
| 🌐 Public Web Hosting | ❌ | ❌ | ✅ | ❌ | ❌ |
| 🤖 AI Model Inference | ❌ | ❌ | ❌ | ✅ | ✅ |
| 🦞 Any Ollama Model | ❌ | ❌ | ❌ | ❌ | ✅ |
| 🤖 AI CLI Tools | ❌ | ✅ | ❌ | ❌ | ✅ |
| 💬 Chat UI | ❌ | ❌ | ❌ | ✅ | ✅ |
| 📨 Discord Notifications | ✅ | ✅ | ✅ | ✅ | ✅ |
| 📨 Telegram Notifications | ✅ | ✅ | ✅ | ✅ | ✅ |
| ⚡ Package Cache | ✅ | ✅ | ✅ | ✅ | ✅ |
| 💾 Data Persists | ✅ | ✅ | ✅ | ✅ | ✅ |
| ⏰ Extendable Sessions | ✅ | ✅ | ✅ | ✅ | ✅ |
| ☁️ Cloudflare Tunnel | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## 📜 License

MIT — use at your own risk. Educational/personal use only.

---

<div align="center">

**Powered by [GitHub Actions](https://github.com/features/actions)**

⭐ Star if this helped you!

</div>
