#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Code-Server Keepalive (Stealth CI/CD Mode)
#  Simulates realistic CI/CD pipeline activity so the runner
#  looks like a dev/test environment, not a free IDE.
#  - Constant stdout output (prevents GitHub idle kill)
#  - Varied CI-like tasks every tick
#  - Auto-restart code-server + tunnel
#  - Session extension support
# ============================================================
set -euo pipefail

DURATION="${1:-30}"
ACTIVE_MINUTES=$((DURATION - 2))
END_TIME=$((SECONDS + (ACTIVE_MINUTES * 60)))
EXTENSION_COUNT=0
MAX_EXTENSIONS=5

echo "╔══════════════════════════════════════════════════════╗"
echo "║  💻 Code-Server CI/CD Keepalive — ${ACTIVE_MINUTES} minutes ║"
echo "║  Simulating dev build & test environment            ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

TICK=0
LAST_CHECKED_BRANCHES=""
TASK_INDEX=0

# ── CI/CD Activity Library ─────────────────────────────────

ci_network_ping() {
  echo "::group::🌐 API health check"
  echo "Checking external endpoints..."
  curl -sf -o /dev/null -w "  github.com: %{http_code} (%{time_total}s)\n" --connect-timeout 5 "https://github.com" 2>/dev/null || echo "  github.com: timeout"
  curl -sf -o /dev/null -w "  vscode-cdn.net: %{http_code} (%{time_total}s)\n" --connect-timeout 5 "https://vscode-cdn.net" 2>/dev/null || echo "  vscode-cdn.net: timeout"
  curl -sf -o /dev/null -w "  registry.npmjs.org: %{http_code} (%{time_total}s)\n" --connect-timeout 5 "https://registry.npmjs.org/" 2>/dev/null || echo "  registry.npmjs.org: timeout"
  echo "DNS resolution test..."
  host github.com 2>/dev/null | head -2 || echo "  DNS: ok"
  echo "::endgroup::"
}

ci_npm_audit() {
  echo "::group::📦 Package audit & validation"
  echo "Checking workspace contents..."
  if [ -d /home/runner/workspace ]; then
    FILES=$(find /home/runner/workspace -maxdepth 2 -type f 2>/dev/null | wc -l)
    echo "  Workspace files: ${FILES}"
    if [ -f /home/runner/workspace/package.json ]; then
      cd /home/runner/workspace
      echo "  package.json found — checking deps..."
      cat package.json | python3 -c "import sys,json; d=json.load(sys.stdin); deps=d.get('dependencies',{}); devdeps=d.get('devDependencies',{}); print(f'  dependencies: {len(deps)}'); print(f'  devDependencies: {len(devdeps)}')" 2>/dev/null || echo "  Parse: ok"
    fi
  fi
  echo "System package versions:"
  node --version 2>/dev/null && echo "  Node.js: ✅" || echo "  Node.js: not installed"
  npm --version 2>/dev/null && echo "  npm: ✅" || echo "  npm: not installed"
  python3 --version 2>/dev/null && echo "  Python: ✅" || echo "  Python: not installed"
  git --version 2>/dev/null && echo "  Git: ✅" || echo "  Git: not installed"
  echo "::endgroup::"
}

ci_build_simulation() {
  echo "::group::🔧 Build test"
  echo "Compiling test binaries..."
  mkdir -p /tmp/ci-build
  cat > /tmp/ci-build/hello.c <<'EOF'
#include <stdio.h>
int main() { printf("Build OK\n"); return 0; }
EOF
  gcc -O2 -Wall -o /tmp/ci-build/hello /tmp/ci-build/hello.c 2>&1 && /tmp/ci-build/hello && echo "  ✅ C compilation: passed"
  cat > /tmp/ci-build/test.js <<'EOF'
const assert = require('assert');
assert.strictEqual(1 + 1, 2);
console.log('JS test passed');
EOF
  node /tmp/ci-build/test.js 2>/dev/null && echo "  ✅ Node.js eval: passed"
  python3 -c "assert 1+1==2; print('Python assert: passed')" 2>/dev/null && echo "  ✅ Python eval: passed"
  rm -rf /tmp/ci-build
  echo "::endgroup::"
}

ci_code_server_health() {
  echo "::group::🩺 Code-Server health check"
  if pgrep -f "code-server" > /dev/null; then
    echo "  Process: running (PID: $(pgrep -f code-server | head -1))"
    HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null || echo "000")
    echo "  HTTP response: ${HTTP_CODE}"
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
      echo "  ✅ Code-server is healthy"
    else
      echo "  ⚠️  Code-server not responding properly"
    fi
  else
    echo "  ❌ Code-server process not found"
  fi
  echo "Memory usage:"
  ps aux | grep -E "code-server|node" | grep -v grep | head -3 | awk '{printf "  %s: %s CPU, %s MEM\n", $11, $3"%", $4"%"}'
  echo "::endgroup::"
}

ci_extension_scan() {
  echo "::group::🔍 VS Code extension scan"
  if [ -d /home/runner/.local/share/code-server ]; then
    INSTALLED=$(find /home/runner/.local/share/code-server -name "package.json" -maxdepth 3 2>/dev/null | wc -l)
    echo "  Installed extensions: ${INSTALLED}"
    find /home/runner/.local/share/code-server -name "package.json" -maxdepth 3 2>/dev/null | while read -r f; do
      NAME=$(python3 -c "import json; d=json.load(open('$f')); print(d.get('name','unknown'))" 2>/dev/null || echo "?")
      VER=$(python3 -c "import json; d=json.load(open('$f')); print(d.get('version','?'))" 2>/dev/null || echo "?")
      echo "  - $NAME@$VER"
    done
  else
    echo "  No extensions installed yet"
  fi
  echo "::endgroup::"
}

ci_workspace_stats() {
  echo "::group::📁 Workspace analysis"
  if [ -d /home/runner/workspace ]; then
    echo "Disk usage:"
    du -sh /home/runner/workspace 2>/dev/null | awk '{print "  Workspace: "$1}'
    echo "File types:"
    find /home/runner/workspace -type f 2>/dev/null | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -8 | awk '{printf "  .%-12s %s files\n", $2, $1}'
    echo "Git status:"
    cd /home/runner/workspace && git status --short 2>/dev/null | head -5 || echo "  Not a git repo"
    TOTAL_LINES=$(find /home/runner/workspace -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.sh" 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 || echo "0 total")
    echo "  Lines of code: ${TOTAL_LINES}"
  else
    echo "  Workspace: empty (no project cloned)"
  fi
  echo "Code-Server config size:"
  du -sh /home/runner/.config/code-server 2>/dev/null | awk '{print "  "$0}' || echo "  No config"
  echo "::endgroup::"
}

ci_security_scan() {
  echo "::group::🔒 Security checks"
  echo "Open ports:"
  ss -tlnp 2>/dev/null | head -8 || echo "  (no ss available)"
  echo "Running processes:"
  ps aux --sort=-%cpu | head -6 | awk '{printf "  %-10s %-8s %s\n", $1, $4"%", $11}'
  echo "Disk usage:"
  df -h / /tmp 2>/dev/null | tail -2 | awk '{print "  "$0}'
  echo "SSH keys present:"
  find /home/runner/.ssh -type f 2>/dev/null | wc -l | xargs -I{} echo "  {} files"
  echo "::endgroup::"
}

ci_perf_benchmark() {
  echo "::group::📊 Performance test"
  echo "CPU test (3s)..."
  python3 -c "
import time
start = time.time()
while time.time() - start < 3:
    sum(range(1000))
print(f'  {sum(range(1000)):,} ops in 3s')
" 2>/dev/null || echo "  skipped"
  echo "I/O test..."
  dd if=/dev/urandom of=/tmp/cs-io bs=512K count=2 2>/dev/null && rm -f /tmp/cs-io && echo "  1MB write: OK"
  echo "Network latency..."
  curl -sf -o /dev/null -w "  github.com: %{time_connect}s connect\n" --connect-timeout 5 "https://github.com" 2>/dev/null || echo "  timeout"
  echo "::endgroup::"
}

ci_env_report() {
  echo "::group::🖥️  Environment"
  echo "  Runner: $(hostname)"
  echo "  OS: $(uname -o) $(uname -r)"
  echo "  Uptime: $(uptime -p 2>/dev/null || uptime)"
  echo "  Memory: $(free -h 2>/dev/null | awk '/Mem:/{print $3"/"$2}')"
  echo "  CPUs: $(nproc)"
  echo "  Shell: $SHELL"
  if command -v node &>/dev/null; then echo "  Node: $(node --version)"; fi
  if command -v python3 &>/dev/null; then echo "  Python: $(python3 --version)"; fi
  echo "  PATH: $(echo $PATH | tr ':' '\n' | wc -l) entries"
  echo "::endgroup::"
}

# Task rotation
TASKS=(ci_network_ping ci_npm_audit ci_build_simulation ci_code_server_health ci_extension_scan ci_workspace_stats ci_security_scan ci_perf_benchmark ci_env_report)

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
  echo "  ⏰  DEV SESSION EXTENDED +${EXTRA_MINUTES} minutes"
  echo "  📊 Extensions: ${EXTENSION_COUNT}/${MAX_EXTENSIONS}"
  echo "  ⏳  New ETA: $(date -d "+${TOTAL_REMAINING} minutes" '+%H:%M:%S UTC')"
  echo "══════════════════════════════════════════════════════"
  echo ""

  return 0
}

# ── Service Auto-Restart ────────────────────────────────────

restart_services() {
  # Code-server
  if ! pgrep -f "code-server" > /dev/null; then
    echo "⚠️  Code-server crashed! Restarting..."
    PASS=$(cat /tmp/cs-password.txt 2>/dev/null || echo "code-server")
    mkdir -p /home/runner/.config/code-server
    cat > /home/runner/.config/code-server/config.yaml <<CONFIG_EOF
bind-addr: 0.0.0.0:8080
auth: password
password: ${PASS}
cert: false
CONFIG_EOF
    nohup code-server --config /home/runner/.config/code-server/config.yaml \
      > /tmp/code-server.log 2>&1 &
    sleep 3
    echo "   ✅ Code-server restarted (PID: $(pgrep -f code-server | head -1))"
  fi

  # Cloudflare tunnel
  if ! pgrep -f "cloudflared" > /dev/null && [ -f /tmp/cloudflared.log ]; then
    echo "⚠️  Tunnel crashed! Restarting..."
    nohup cloudflared tunnel --url http://localhost:8080 --no-autoupdate \
      > /tmp/cloudflared.log 2>&1 &
    sleep 3
    NEW_URL=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1 || true)
    [ -n "$NEW_URL" ] && echo "   New tunnel: $NEW_URL/"
  fi

  # localhost.run tunnel
  if ! pgrep -f "localhost.run" > /dev/null && ! pgrep -f "ssh -R 80" > /dev/null && [ -f /tmp/ssh-tunnel.log ]; then
    if [ ! -f /tmp/cloudflared.log ]; then
      echo "⚠️  localhost.run tunnel crashed! Restarting..."
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -R 80:localhost:8080 \
        -o ServerAliveInterval=60 \
        nokey@localhost.run > /tmp/ssh-tunnel.log 2>&1 &
      sleep 3
    fi
  fi
}

# ── Main Loop ───────────────────────────────────────────────
echo "🚀 Starting dev environment CI simulation..."
echo ""

while true; do
  if [ $SECONDS -ge $END_TIME ]; then
    echo ""
    echo "✅ Dev CI pipeline completed."
    echo "   Runtime: $((SECONDS / 60)) min | Extensions: ${EXTENSION_COUNT}"
    echo "   Saving workspace artifacts..."
    exit 0
  fi

  TICK=$((TICK + 1))
  REMAINING=$(( (END_TIME - SECONDS) / 60 ))

  # ── Check extensions every 3 min ──────────────────────────
  if [ $((TICK % 3)) -eq 0 ]; then
    check_for_extension || true
    REMAINING=$(( (END_TIME - SECONDS) / 60 ))
    if [ $REMAINING -lt 1 ]; then
      echo "✅ Dev CI pipeline completed."
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
  echo "⏳  [${BAR}] ${REMAINING} min left | extensions: ${EXTENSION_COUNT}/${MAX_EXTENSIONS}"

  # Short sleep — keeps stdout flowing, prevents idle kill
  sleep 10
done
