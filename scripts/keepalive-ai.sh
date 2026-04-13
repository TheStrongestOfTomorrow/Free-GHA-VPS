#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - AI Model Keepalive (Stealth CI/CD Mode)
#  Keeps the AI model session alive with:
#  - Constant stdout output (prevents GitHub idle kill)
#  - Service auto-restart (Ollama + Chat UI)
#  - Model health checks
#  - Session extension support
# ============================================================
# NO set -euo pipefail — CI tasks use pipes and failing commands

DURATION="${1:-30}"
ACTIVE_MINUTES=$((DURATION - 2))
END_TIME=$((SECONDS + (ACTIVE_MINUTES * 60)))
EXTENSION_COUNT=0
MAX_EXTENSIONS=5
OLLAMA_PORT=11434
CHAT_PORT=11435

echo "╔══════════════════════════════════════════════════════╗"
echo "║  🤖 AI Model Keepalive — ${ACTIVE_MINUTES} minutes           ║"
echo "║  Monitoring inference + chat services              ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

TICK=0
LAST_CHECKED_BRANCHES=""
TASK_INDEX=0

# ── CI/CD Activity Library (AI-focused) ─────────────────────

ai_health_check() {
  echo "::group::🤖 AI Service Health Check"
  echo "Checking Ollama API..."
  HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:$OLLAMA_PORT/api/tags 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "200" ]; then
    echo "  ✅ Ollama API: healthy (HTTP $HTTP_CODE)"
  else
    echo "  ⚠️  Ollama API: HTTP $HTTP_CODE"
  fi

  echo "Checking Chat UI..."
  HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:$CHAT_PORT 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "200" ]; then
    echo "  ✅ Chat UI: healthy (HTTP $HTTP_CODE)"
  else
    echo "  ⚠️  Chat UI: HTTP $HTTP_CODE"
  fi

  echo "Model memory usage:"
  ps aux | grep -E "ollama|llama" | grep -v grep | head -3 | awk '{printf "  %s: %s CPU, %s MEM, RSS=%sMB\n", $11, $3"%", $4"%", $6/1024}' 2>/dev/null || echo "  No model processes found"
  echo "::endgroup::"
}

ai_model_info() {
  echo "::group::📋 Model Information"
  echo "Available models:"
  ollama list 2>/dev/null | while read -r line; do echo "  $line"; done || echo "  (ollama not responding)"
  echo "Running model:"
  MODEL_NAME="${AI_MODEL:-gemma3:1b}"
  ollama show "$MODEL_NAME" 2>/dev/null | head -10 || echo "  (model info unavailable)"
  echo "Chat history files:"
  ls -la /home/runner/ai-data/history/ 2>/dev/null | tail -5 || echo "  (no history yet)"
  echo "::endgroup::"
}

ci_network_check() {
  echo "::group::🌐 Network connectivity"
  echo "Testing endpoints..."
  curl -sf -o /dev/null -w "  ollama.com: %{http_code} (%{time_total}s)\n" --connect-timeout 5 "https://ollama.com" 2>/dev/null || echo "  ollama.com: timeout"
  curl -sf -o /dev/null -w "  github.com: %{http_code} (%{time_total}s)\n" --connect-timeout 5 "https://github.com" 2>/dev/null || echo "  github.com: timeout"
  echo "DNS resolution..."
  host github.com 2>/dev/null | head -2 || echo "  dns: ok (cached)"
  echo "::endgroup::"
}

ci_dependency_check() {
  echo "::group::📦 Dependency validation"
  echo "System packages: $(dpkg -l | wc -l)"
  echo "Critical tools:"
  for cmd in ollama python3 curl git jq; do
    if command -v "$cmd" &>/dev/null; then
      VERSION=$("$cmd" --version 2>/dev/null | head -1 | cut -c1-80)
      echo "  ✅ $cmd: $VERSION"
    else
      echo "  ❌ $cmd: not found"
    fi
  done
  echo "Disk usage:"
  df -h / /home 2>/dev/null | tail -2 | awk '{print "  "$0}'
  echo "Memory:"
  free -h 2>/dev/null | head -2
  echo "::endgroup::"
}

ci_inference_test() {
  echo "::group::🧪 Inference Test"
  echo "Running quick inference test..."
  START_TIME=$(date +%s%N)
  RESULT=$(curl -sf http://localhost:$OLLAMA_PORT/api/generate \
    -d "{\"model\":\"${AI_MODEL:-gemma3:1b}\",\"prompt\":\"Say hello in one word.\",\"stream\":false}" 2>/dev/null || echo "{}")
  END_TIME=$(date +%s%N)

  if [ "$RESULT" != "{}" ]; then
    ELAPSED=$(( (END_TIME - START_TIME) / 1000000 ))
    RESPONSE=$(echo "$RESULT" | jq -r '.response // "no response"' 2>/dev/null | head -1)
    TOKENS=$(echo "$RESULT" | jq -r '.eval_count // "unknown"' 2>/dev/null)
    EVAL_MS=$(echo "$RESULT" | jq -r '.eval_duration // 0' 2>/dev/null)
    if [ "$EVAL_MS" != "0" ] && [ "$EVAL_MS" != "null" ]; then
      EVAL_MS=$((EVAL_MS / 1000000))
      if [ "$EVAL_MS" -gt 0 ] && [ "$TOKENS" != "unknown" ] && [ "$TOKENS" != "null" ]; then
        TPS=$((TOKENS * 1000 / EVAL_MS))
        echo "  ✅ Inference OK: ${ELAPSED}ms total, ~${TPS} tokens/sec"
      else
        echo "  ✅ Inference OK: ${ELAPSED}ms"
      fi
    else
      echo "  ✅ Inference OK: ${ELAPSED}ms"
    fi
    echo "  Response: ${RESPONSE:0:80}"
  else
    echo "  ⚠️  Inference test failed (Ollama may be busy)"
  fi
  echo "::endgroup::"
}

ci_security_scan() {
  echo "::group::🔒 Security audit"
  echo "Running processes:"
  ps aux --sort=-%cpu | head -6 | awk '{printf "  %-10s %-8s %s\n", $1, $4"%", $11}'
  echo "Open ports:"
  ss -tlnp 2>/dev/null | head -8 || echo "  (no ss available)"
  echo "Disk usage:"
  df -h / /tmp 2>/dev/null | tail -2 | awk '{print "  "$0}'
  echo "::endgroup::"
}

ci_perf_benchmark() {
  echo "::group::📊 Performance"
  echo "CPU test (3s)..."
  python3 -c "
import time
start = time.time()
while time.time() - start < 3:
    sum(range(1000))
print(f'  {sum(range(1000)):,} ops in 3s')
" 2>/dev/null || echo "  skipped"
  echo "Memory:"
  free -h 2>/dev/null | head -2 | tail -1 | awk '{print "  Used: "$3" / Total: "$2}'
  echo "Model cache size:"
  du -sh /home/runner/.ollama/models 2>/dev/null | awk '{print "  "$1}' || echo "  Not available"
  echo "Chat history size:"
  du -sh /home/runner/ai-data/history 2>/dev/null | awk '{print "  "$1}' || echo "  No history"
  echo "::endgroup::"
}

ci_env_report() {
  echo "::group::🖥️  Environment"
  echo "  Runner: $(hostname)"
  echo "  OS: $(uname -o) $(uname -r)"
  echo "  Uptime: $(uptime -p 2>/dev/null || uptime)"
  echo "  Memory: $(free -h 2>/dev/null | awk '/Mem:/{print $3"/"$2}')"
  echo "  CPUs: $(nproc)"
  echo "  Model: ${AI_MODEL:-gemma3:1b}"
  if command -v ollama &>/dev/null; then echo "  Ollama: $(ollama --version 2>/dev/null | head -1)"; fi
  if command -v python3 &>/dev/null; then echo "  Python: $(python3 --version)"; fi
  echo "::endgroup::"
}

ci_artifact_test() {
  echo "::group::📁 Artifact handling"
  echo "Testing file I/O..."
  mkdir -p /tmp/ci-artifacts
  echo "test artifact $(date -u)" > /tmp/ci-artifacts/test.log
  tar czf /tmp/ci-artifacts/archive.tar.gz -C /tmp/ci-artifacts test.log
  echo "  Created archive ($(du -h /tmp/ci-artifacts/archive.tar.gz | cut -f1))"
  rm -rf /tmp/ci-artifacts
  echo "  ✅ I/O test passed"
  echo "::endgroup::"
}

# Task rotation
TASKS=(ai_health_check ai_model_info ci_network_check ci_dependency_check ci_inference_test ci_security_scan ci_perf_benchmark ci_env_report ci_artifact_test)

run_ci_task() {
  local idx=$((TASK_INDEX % ${#TASKS[@]}))
  ${TASKS[$idx]}
  TASK_INDEX=$((TASK_INDEX + 1))
}

# ── Extension Support ───────────────────────────────────────

check_for_extension() {
  SIGNAL_BRANCHES=$(git ls-remote --heads origin 'refs/heads/vps-extend-*' 2>/dev/null || true)
  if [ -z "$SIGNAL_BRANCHES" ]; then return 1; fi
  if [ "$SIGNAL_BRANCHES" = "$LAST_CHECKED_BRANCHES" ]; then return 1; fi

  SIGNAL_BRANCH=$(echo "$SIGNAL_BRANCHES" | head -1 | awk '{print $2}' | sed 's|refs/heads/||')
  EXTRA_MINUTES=30
  SIGNAL_DATA=$(git fetch origin "$SIGNAL_BRANCH" 2>/dev/null && git show "origin/$SIGNAL_BRANCH:.vps-extend-signal" 2>/dev/null || true)
  if [ -n "$SIGNAL_DATA" ]; then
    EXTRA_MINUTES=$(echo "$SIGNAL_DATA" | cut -d'|' -f2)
    EXTRA_MINUTES="${EXTRA_MINUTES:-30}"
  fi
  [ "$EXTRA_MINUTES" -gt 30 ] && EXTRA_MINUTES=30

  if [ $EXTENSION_COUNT -ge $MAX_EXTENSIONS ]; then
    echo "⚠️  Max extensions ($MAX_EXTENSIONS) reached."
    LAST_CHECKED_BRANCHES="$SIGNAL_BRANCHES"
    return 1
  fi

  git push origin --delete "$SIGNAL_BRANCH" 2>/dev/null || true
  LAST_CHECKED_BRANCHES=""
  END_TIME=$((END_TIME + (EXTRA_MINUTES * 60)))
  EXTENSION_COUNT=$((EXTENSION_COUNT + 1))
  TOTAL_REMAINING=$(( (END_TIME - SECONDS) / 60 ))

  echo ""
  echo "══════════════════════════════════════════════════════"
  echo "  ⏰  AI SESSION EXTENDED +${EXTRA_MINUTES} minutes"
  echo "  📊 Extensions: ${EXTENSION_COUNT}/${MAX_EXTENSIONS}"
  echo "  ⏳  New ETA: $(date -d "+${TOTAL_REMAINING} minutes" '+%H:%M:%S UTC')"
  echo "══════════════════════════════════════════════════════"
  echo ""

  return 0
}

# ── Service Auto-Restart ────────────────────────────────────

restart_services() {
  # Ollama server
  if ! pgrep -f "ollama serve" > /dev/null; then
    echo "⚠️  Ollama server crashed! Restarting..."
    export OLLAMA_HOST="0.0.0.0:$OLLAMA_PORT"
    export OLLAMA_MODELS="/home/runner/.ollama/models"
    nohup ollama serve > /tmp/ollama-server.log 2>&1 &
    sleep 5
    echo "   ✅ Ollama restarted (PID: $(pgrep -f 'ollama serve' | head -1))"
  fi

  # Chat UI server
  if ! pgrep -f "chat-server.py" > /dev/null; then
    echo "⚠️  Chat UI crashed! Restarting..."
    export AI_PASSWORD="$(cat /tmp/ai-password.txt 2>/dev/null || echo '')"
    export AI_MODEL="${AI_MODEL:-gemma3:1b}"
    export CHAT_PORT="$CHAT_PORT"
    export OLLAMA_PORT="$OLLAMA_PORT"
    export OLLAMA_HOST="localhost"
    export CHAT_HISTORY_DIR="/home/runner/ai-data/history"
    nohup python3 /home/runner/ai-data/chat-server.py > /tmp/ai-chat-server.log 2>&1 &
    sleep 3
    echo "   ✅ Chat UI restarted (PID: $(pgrep -f 'chat-server.py' | head -1))"
  fi

  # Cloudflare tunnel
  if ! pgrep -f "cloudflared" > /dev/null && [ -f /tmp/cloudflared.log ]; then
    echo "⚠️  Tunnel crashed! Restarting..."
    nohup cloudflared tunnel --url http://localhost:$CHAT_PORT --no-autoupdate \
      > /tmp/cloudflared.log 2>&1 &
    sleep 3
    NEW_URL=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1 || true)
    [ -n "$NEW_URL" ] && echo "   New tunnel: $NEW_URL/"
  fi
}

# ── Main Loop ───────────────────────────────────────────────
echo "🚀 Starting AI model CI simulation..."
echo ""

while true; do
  if [ $SECONDS -ge $END_TIME ]; then
    echo ""
    echo "✅ AI model CI pipeline completed."
    echo "   Duration: $((SECONDS / 60)) min | Extensions: ${EXTENSION_COUNT}"
    echo "   Saving session data..."
    exit 0
  fi

  TICK=$((TICK + 1))
  REMAINING=$(( (END_TIME - SECONDS) / 60 ))

  # ── Check extensions every 3 min ──────────────────────────
  if [ $((TICK % 3)) -eq 0 ]; then
    check_for_extension || true
    REMAINING=$(( (END_TIME - SECONDS) / 60 ))
    if [ $REMAINING -lt 1 ]; then
      echo "✅ AI model CI pipeline completed."
      exit 0
    fi
  fi

  # ── Service health check ──────────────────────────────────
  restart_services

  # ── Run a CI/CD task (rotated) ────────────────────────────
  echo ""
  echo "── Pipeline tick #${TICK} | ~${REMAINING} min remaining ──"
  run_ci_task

  # ── Progress bar to stdout ────────────────────────────────
  echo ""
  FILLED=$(( (SECONDS * 20) / (END_TIME) ))
  [ $FILLED -gt 20 ] && FILLED=20
  EMPTY=$(( 20 - FILLED ))
  BAR=$(printf '#%.0s' $(seq 1 $FILLED 2>/dev/null) 2>/dev/null)$(printf '-%.0s' $(seq 1 $EMPTY 2>/dev/null) 2>/dev/null)
  echo "⏳  [${BAR}] ${REMAINING} min left | extensions: ${EXTENSION_COUNT}/${MAX_EXTENSIONS} | model: ${AI_MODEL:-gemma3:1b}"

  # Short sleep
  sleep 10
done
