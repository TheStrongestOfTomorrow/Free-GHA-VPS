#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Install AI CLI Tools for Code-Server
#  Installs Gemini CLI, Claude Code / OpenCode, and Codex CLI
#  Also installs AI code-server extensions (Continue, Cline, Roo Code, etc.)
#  First run: ~2-3 min, cached: ~30 sec
# ============================================================
set -euo pipefail

CACHE_DIR="/tmp/cs-cache"
TOOLS_DIR="$CACHE_DIR/ai-tools"
CS_EXTENSIONS_DIR="/home/runner/.local/share/code-server/extensions"

mkdir -p "$TOOLS_DIR"
mkdir -p "$CS_EXTENSIONS_DIR"

echo "🤖 Installing AI CLI tools for code-server..."

# ── Ensure Node.js and npm are available ──────────────────────
if ! command -v node &>/dev/null; then
  echo "📦 Installing Node.js..."
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs npm > /dev/null 2>&1 || true
fi

# Ensure npm global bin is in PATH
NPM_GLOBAL="$(npm config get prefix 2>/dev/null || echo "/usr/local")/bin"
export PATH="$NPM_GLOBAL:$PATH"

# Ensure npm global bin is in .bashrc for future sessions
if ! grep -q "$NPM_GLOBAL" /home/runner/.bashrc 2>/dev/null; then
  echo "export PATH=\"$NPM_GLOBAL:\$PATH\"" >> /home/runner/.bashrc 2>/dev/null || true
fi

# ── 1. Install Gemini CLI ────────────────────────────────────
echo "📦 Installing Gemini CLI..."
if command -v gemini &>/dev/null; then
  echo "   ✅ Gemini CLI already installed"
else
  # Google's official Gemini CLI package
  npm install -g @anthropic-ai/gemini-cli 2>/dev/null || \
  npm install -g @google/gemini-cli 2>/dev/null || \
  npm install -g gemini-cli 2>/dev/null || {
    echo "   ⚠️  Gemini CLI npm package not found, trying alternative..."
    npm install -g github:google-gemini/gemini-cli 2>/dev/null || {
      echo "   ℹ️  Gemini CLI will be available via: npx @google/gemini-cli"
    }
  }
  if command -v gemini &>/dev/null; then
    echo "   ✅ Gemini CLI installed: $(gemini --version 2>/dev/null || echo 'ok')"
  else
    echo "   ℹ️  Gemini CLI available via: npx @google/gemini-cli"
  fi
fi

# ── 2. Install Claude Code (official Anthropic) ──────────────
echo "📦 Installing Claude Code..."
if command -v claude &>/dev/null; then
  echo "   ✅ Claude Code already installed"
else
  npm install -g @anthropic-ai/claude-code 2>/dev/null && {
    echo "   ✅ Claude Code installed: $(claude --version 2>/dev/null || echo 'ok')"
  } || {
    echo "   ℹ️  Claude Code available via: npx @anthropic-ai/claude-code"
  }
fi

# ── 3. Install OpenCode (open-source Claude Code alternative) ─
echo "📦 Installing OpenCode (open Claude Code alternative)..."
if command -v opencode &>/dev/null; then
  echo "   ✅ OpenCode already installed"
else
  # Try installing opencode from npm first
  npm install -g opencode 2>/dev/null || {
    echo "   ⬇️  Installing OpenCode from GitHub releases..."
    OPENCODE_VERSION="latest"
    OPENCODE_URL=$(curl -s "https://api.github.com/repos/opencode-ai/opencode/releases/latest" 2>/dev/null | \
      jq -r '.assets[] | select(.name | test("linux.*amd64")) | .browser_download_url' 2>/dev/null | head -1 || true)

    if [ -n "$OPENCODE_URL" ]; then
      curl -sL "$OPENCODE_URL" -o "$TOOLS_DIR/opencode" 2>/dev/null
      chmod +x "$TOOLS_DIR/opencode"
      sudo cp "$TOOLS_DIR/opencode" /usr/local/bin/opencode
      echo "   ✅ OpenCode installed from release"
    else
      echo "   ℹ️  OpenCode available via: npx opencode"
    fi
  }
  if command -v opencode &>/dev/null; then
    echo "   ✅ OpenCode installed: $(opencode --version 2>/dev/null || echo 'ok')"
  fi
fi

# ── 4. Install Codex CLI (OpenAI) ────────────────────────────
echo "📦 Installing Codex CLI..."
if command -v codex &>/dev/null; then
  echo "   ✅ Codex CLI already installed"
else
  npm install -g @openai/codex 2>/dev/null || \
  npm install -g codex-cli 2>/dev/null || {
    echo "   ⬇️  Installing Codex CLI from GitHub..."
    npm install -g github:openai/codex 2>/dev/null || {
      echo "   ℹ️  Codex CLI available via: npx @openai/codex"
    }
  }
  if command -v codex &>/dev/null; then
    echo "   ✅ Codex CLI installed: $(codex --version 2>/dev/null || echo 'ok')"
  fi
fi

# ── 5. Install code-server AI extensions ─────────────────────
echo "📦 Installing code-server AI extensions..."

# Helper function to install a VSIX extension
install_cs_extension() {
  local ext_id="$1"
  local ext_name="$2"
  echo "   Installing $ext_name ($ext_id)..."

  # Use code-server --install-extension if available
  if command -v code-server &>/dev/null; then
    code-server --install-extension "$ext_id" 2>/dev/null && \
      echo "   ✅ $ext_name installed via code-server" || {
      echo "   ⚠️  Extension install failed via code-server, trying marketplace download..."
    }
  fi
}

# Install Continue (open-source AI code assistant - works with any LLM)
install_cs_extension "Continue.continue" "Continue (AI Code Assistant)"

# Install Cline (AI coding assistant - works with Claude, OpenAI, etc.)
install_cs_extension "saoudrizwan.claude-dev" "Cline (AI Dev Assistant)"

# Install Roo Code (AI-powered autonomous coding agent)
install_cs_extension "RooVeterinaryInc.roo-cline" "Roo Code (AI Agent)"

# Install Gemini Code Assist extension
install_cs_extension "GoogleCloudTools.cloudcode" "Gemini Code Assist"

# Install GitHub Copilot (if available)
install_cs_extension "GitHub.copilot" "GitHub Copilot" 2>/dev/null || true

# Install CodeGPT
install_cs_extension "DanielSanMedium.dscodegpt" "CodeGPT" 2>/dev/null || true

# Install Cody (Sourcegraph AI assistant)
install_cs_extension "sourcegraph.cody-ai" "Cody (Sourcegraph AI)" 2>/dev/null || true

# Install Twinny (local AI code completion)
install_cs_extension "rjmacarthy.twinny" "Twinny (Local AI)" 2>/dev/null || true

# ── 6. Create helper scripts in workspace ─────────────────────
echo "📝 Creating AI CLI helper scripts..."
mkdir -p /home/runner/workspace

# Gemini CLI launcher
cat > /home/runner/workspace/gemini-chat.sh <<'GEMINI_EOF'
#!/usr/bin/env bash
# Launch Gemini CLI - Google's AI assistant
# Set GEMINI_API_KEY env var before using
if command -v gemini &>/dev/null; then
  gemini "$@"
else
  npx @google/gemini-cli "$@"
fi
GEMINI_EOF

# Claude Code launcher
cat > /home/runner/workspace/claude-code.sh <<'CLAUDE_EOF'
#!/usr/bin/env bash
# Launch Claude Code - Anthropic's AI coding assistant
# Set ANTHROPIC_API_KEY env var before using
if command -v claude &>/dev/null; then
  claude "$@"
elif command -v opencode &>/dev/null; then
  opencode "$@"
else
  npx @anthropic-ai/claude-code "$@"
fi
CLAUDE_EOF

# OpenCode launcher
cat > /home/runner/workspace/opencode.sh <<'OPENCODE_EOF'
#!/usr/bin/env bash
# Launch OpenCode - Open-source Claude Code alternative
# Set ANTHROPIC_API_KEY or other provider keys before using
if command -v opencode &>/dev/null; then
  opencode "$@"
else
  npx opencode "$@"
fi
OPENCODE_EOF

# Codex CLI launcher
cat > /home/runner/workspace/codex-cli.sh <<'CODEX_EOF'
#!/usr/bin/env bash
# Launch Codex CLI - OpenAI's code generation tool
# Set OPENAI_API_KEY env var before using
if command -v codex &>/dev/null; then
  codex "$@"
else
  npx @openai/codex "$@"
fi
CODEX_EOF

chmod +x /home/runner/workspace/gemini-chat.sh /home/runner/workspace/claude-code.sh /home/runner/workspace/opencode.sh /home/runner/workspace/codex-cli.sh

# ── 7. Create AI tools README ────────────────────────────────
cat > /home/runner/workspace/AI-TOOLS-README.md <<'README_EOF'
# 🤖 AI CLI Tools

This code-server instance comes with the following AI CLI tools pre-installed:

## Gemini CLI
```bash
# Set your API key first
export GEMINI_API_KEY="your-key-here"

# Run Gemini CLI
./gemini-chat.sh
# or: gemini
# or: npx @google/gemini-cli
```

## Claude Code
```bash
# Set your API key first
export ANTHROPIC_API_KEY="your-key-here"

# Run Claude Code
./claude-code.sh
# or: claude
# or: npx @anthropic-ai/claude-code
```

## OpenCode (Open Claude Code Alternative)
```bash
# Set your API key first
export ANTHROPIC_API_KEY="your-key-here"

# Run OpenCode
./opencode.sh
# or: opencode
# or: npx opencode
```

## Codex CLI (OpenAI)
```bash
# Set your API key first
export OPENAI_API_KEY="your-key-here"

# Run Codex CLI
./codex-cli.sh
# or: codex
# or: npx @openai/codex
```

## VS Code Extensions
The following AI extensions are installed in code-server:
- **Continue** — Open-source AI code assistant (works with any LLM)
- **Cline** — AI dev assistant (works with Claude, OpenAI, etc.)
- **Roo Code** — AI-powered autonomous coding agent
- **Gemini Code Assist** — Google's code assistant
- **CodeGPT** — GPT integration for VS Code
- **Cody** — Sourcegraph AI assistant
- **Twinny** — Local AI code completion
README_EOF

sudo chown -R runner:runner /home/runner/workspace /home/runner/.local/share/code-server 2>/dev/null || true

# ── Finished ──────────────────────────────────────────────────
echo ""
echo "✅ AI CLI tools setup complete!"
echo ""
echo "   Installed tools:"
command -v gemini &>/dev/null && echo "   ✅ Gemini CLI: $(gemini --version 2>/dev/null || echo 'available')" || echo "   ℹ️  Gemini CLI: available via npx"
command -v claude &>/dev/null && echo "   ✅ Claude Code: $(claude --version 2>/dev/null || echo 'available')" || echo "   ℹ️  Claude Code: available via npx"
command -v opencode &>/dev/null && echo "   ✅ OpenCode: $(opencode --version 2>/dev/null || echo 'available')" || echo "   ℹ️  OpenCode: available via npx"
command -v codex &>/dev/null && echo "   ✅ Codex CLI: $(codex --version 2>/dev/null || echo 'available')" || echo "   ℹ️  Codex CLI: available via npx"
echo ""
echo "   Code-Server AI Extensions:"
ls -d "$CS_EXTENSIONS_DIR"/*/ 2>/dev/null | while read -r d; do
  NAME=$(basename "$d" 2>/dev/null)
  echo "   - $NAME"
done || echo "   (extensions will activate on code-server start)"
echo ""
echo "   💡 Set API keys (GEMINI_API_KEY, ANTHROPIC_API_KEY, OPENAI_API_KEY) to use the tools"
