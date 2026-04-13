#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Start Code-Server
#  Launches code-server with password, bound to 0.0.0.0:8080
# ============================================================
set -euo pipefail

INPUT_PASSWORD="${1:-}"

echo "🚀 Starting code-server..."

# ── Set password ──────────────────────────────────────────────
if [ -n "$INPUT_PASSWORD" ] && [ ${#INPUT_PASSWORD} -ge 6 ]; then
  CS_PASS="$INPUT_PASSWORD"
else
  if [ -n "$INPUT_PASSWORD" ] && [ ${#INPUT_PASSWORD} -lt 6 ]; then
    echo "⚠️  Password too short (min 6), auto-generating..."
  fi
  CS_PASS=$(openssl rand -base64 12 | tr -d '=/+' | head -c 12)
fi

# Save password (restrict permissions)
echo "$CS_PASS" > /tmp/cs-password.txt
chmod 600 /tmp/cs-password.txt
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "CS_PASSWORD=$CS_PASS" >> "$GITHUB_ENV"
fi

# ── Kill any existing code-server ────────────────────────────
pkill -f code-server 2>/dev/null || true
sleep 1

# ── Write config ─────────────────────────────────────────────
mkdir -p /home/runner/.config/code-server
cat > /home/runner/.config/code-server/config.yaml <<CONFIG_EOF
bind-addr: 0.0.0.0:8080
auth: password
password: ${CS_PASS}
cert: false
CONFIG_EOF

sudo chown -R runner:runner /home/runner/.config/code-server

# ── Start code-server ────────────────────────────────────────
nohup code-server --config /home/runner/.config/code-server/config.yaml \
  > /tmp/code-server.log 2>&1 &
CS_PID=$!
sleep 3

# ── Verify ────────────────────────────────────────────────────
READY=false
if kill -0 $CS_PID 2>/dev/null; then
  for i in $(seq 1 30); do
    if curl -sf http://localhost:8080 > /dev/null 2>&1; then
      echo "✅ Code-server is running!"
      echo "   PID: $CS_PID"
      echo "   Port: 8080"
      echo "   Password: $CS_PASS"
      echo "CS_PID=$CS_PID" >> "${GITHUB_ENV:-/dev/null}"
      READY=true
      break
    fi
    sleep 1
  done
fi

if [ "$READY" = false ]; then
  echo "❌ Code-server failed to start or not responding!"
  echo "   PID check: $(kill -0 $CS_PID 2>/dev/null && echo 'alive' || echo 'dead')"
  echo "   Logs:"
  cat /tmp/code-server.log
  exit 1
fi
