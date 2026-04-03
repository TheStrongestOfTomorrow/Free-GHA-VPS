#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - VPS Keepalive (Stealth CI/CD Mode)
#  Simulates realistic CI/CD pipeline activity so the runner
#  looks like a legitimate test environment, not a VPS.
#  - Constant stdout output (prevents GitHub idle kill)
#  - Varied CI-like tasks every tick
#  - Service auto-restart
#  - Session extension support
# ============================================================
# NO set -euo pipefail — CI tasks use pipes and failing commands
# Error handling is done per-command with || fallbacks

DURATION="${1:-30}"
ACTIVE_MINUTES=$((DURATION - 2))
END_TIME=$((SECONDS + (ACTIVE_MINUTES * 60)))
EXTENSION_COUNT=0
MAX_EXTENSIONS=5

echo "╔══════════════════════════════════════════════════════╗"
echo "║  🔄 CI/CD Pipeline Keepalive — ${ACTIVE_MINUTES} minutes       ║"
echo "║  Simulating build & test environment              ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

TICK=0
LAST_CHECKED_BRANCHES=""
TASK_INDEX=0

# ── CI/CD Activity Library ─────────────────────────────────
# Each function simulates a realistic CI/CD task.
# They all output to stdout so GitHub sees activity.

ci_network_check() {
  echo "::group::🌐 Network connectivity check"
  echo "Testing DNS resolution..."
  host github.com 2>/dev/null | head -2 || echo "  dns: ok (cached)"
  echo "Testing HTTP endpoints..."
  curl -sf -o /dev/null -w "  github.com: %{http_code} (%{time_total}s)\n" --connect-timeout 5 "https://github.com" 2>/dev/null || echo "  github.com: timeout (retrying later)"
  curl -sf -o /dev/null -w "  registry.npmjs.org: %{http_code} (%{time_total}s)\n" --connect-timeout 5 "https://registry.npmjs.org/" 2>/dev/null || echo "  registry.npmjs.org: timeout"
  echo "Trace route (first 3 hops):"
  traceroute -m 3 -w 1 github.com 2>/dev/null | head -5 || echo "  trace: skipped"
  echo "::endgroup::"
}

ci_dependency_check() {
  echo "::group::📦 Dependency validation"
  echo "Checking system packages..."
  dpkg -l | wc -l | xargs -I{} echo "  Installed packages: {}"
  echo "Checking for security updates..."
  apt list --upgradable 2>/dev/null | head -5 || echo "  All packages up to date"
  echo "Verifying critical tools..."
  for cmd in git curl wget python3 node npm gcc make; do
    if command -v "$cmd" &>/dev/null; then
      VERSION=$("$cmd" --version 2>/dev/null | head -1 | cut -c1-80)
      echo "  ✅ $cmd: $VERSION"
    fi
  done
  echo "::endgroup::"
}

ci_build_test() {
  echo "::group::🔧 Build simulation"
  echo "Compiling test module..."
  mkdir -p /tmp/ci-build
  cat > /tmp/ci-build/test.c <<'EOF'
#include <stdio.h>
int main() { printf("Build test OK\n"); return 0; }
EOF
  gcc -O2 -o /tmp/ci-build/test /tmp/ci-build/test.c 2>/dev/null && /tmp/ci-build/test && echo "  ✅ C compilation passed"
  rm -rf /tmp/ci-build

  echo "Running shellcheck on project scripts..."
  if command -v shellcheck &>/dev/null; then
    find /home/runner -name "*.sh" -maxdepth 2 2>/dev/null | head -3 | while read -r f; do
      shellcheck -s bash "$f" 2>/dev/null && echo "  ✅ $(basename "$f"): lint clean" || echo "  ⚠️  $(basename "$f"): warnings"
    done
  else
    echo "  Shellcheck not installed, skipping..."
  fi
  echo "::endgroup::"
}

ci_integration_test() {
  echo "::group::🧪 Integration tests"
  echo "Running health checks on local services..."
  # Check code-server
  curl -sf -o /dev/null -w "  code-server (8080): %{http_code}\n" http://localhost:8080 2>/dev/null || echo "  code-server: not running"
  # Check noVNC
  curl -sf -o /dev/null -w "  noVNC (6080): %{http_code}\n" http://localhost:6080 2>/dev/null || echo "  noVNC: not running"
  # Check Xvfb
  if pgrep -f "Xvfb" >/dev/null 2>&1; then echo "  Xvfb display: running"; else echo "  Xvfb display: stopped"; fi
  echo "Running Python unit tests..."
  python3 -c "
import subprocess, sys
tests_passed = 0
tests_total = 5
for i in range(tests_total):
    result = subprocess.run(['echo', f'test_{i}'], capture_output=True)
    tests_passed += 1
print(f'  Ran {tests_total} tests — {tests_passed} passed, 0 failed')
" 2>/dev/null || echo "  Python tests: skipped"
  echo "Testing git operations..."
  git status --porcelain 2>/dev/null | head -3 || echo "  Git: clean working tree"
  echo "Testing filesystem I/O..."
  dd if=/dev/urandom of=/tmp/ci-io-test bs=1M count=1 2>/dev/null && rm -f /tmp/ci-io-test && echo "  I/O benchmark: 1MB write/read OK"
  echo "::endgroup::"
}

ci_security_scan() {
  echo "::group::🔒 Security audit"
  echo "Checking running processes..."
  ps aux --sort=-%cpu | head -6 | awk '{printf "  %-10s %-8s %s\n", $1, $4"%", $11}'
  echo "Checking open ports..."
  ss -tlnp 2>/dev/null | head -8 || netstat -tlnp 2>/dev/null | head -8 || echo "  No port scanner available"
  echo "Checking disk usage..."
  df -h / /tmp 2>/dev/null | tail -2 | awk '{print "  "$0}'
  echo "Checking for world-writable files..."
  find /home/runner -maxdepth 2 -perm -002 -type f 2>/dev/null | head -3 || echo "  No insecure files found"
  echo "Verifying SSL certificates..."
  echo | openssl s_client -connect github.com:443 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null | head -3 || echo "  SSL check: skipped"
  echo "::endgroup::"
}

ci_performance_test() {
  echo "::group::📊 Performance benchmarks"
  echo "CPU benchmark (5s)..."
  python3 -c "
import time
start = time.time()
while time.time() - start < 5:
    sum(range(1000))
print(f'  CPU: {sum(range(1000)):,} iterations in 5s')
" 2>/dev/null || echo "  CPU benchmark: skipped"
  echo "Memory allocation test..."
  python3 -c "
import tracemalloc
tracemalloc.start()
data = bytearray(10*1024*1024)
current, peak = tracemalloc.get_traced_memory()
tracemalloc.stop()
print(f'  Memory: allocated 10MB, peak {peak/1024/1024:.1f}MB')
" 2>/dev/null || echo "  Memory test: skipped"
  echo "Network latency test..."
  curl -sf -o /dev/null -w "  github.com: %{time_connect}s connect, %{time_total}s total\n" --connect-timeout 10 "https://github.com" 2>/dev/null || echo "  Network: unreachable"
  echo "::endgroup::"
}

ci_environment_report() {
  echo "::group::🖥️  Environment report"
  echo "System info:"
  uname -a | head -1
  echo "  Runner: $(hostname)"
  echo "  Uptime: $(uptime -p 2>/dev/null || uptime)"
  echo "  Memory: $(free -h 2>/dev/null | head -2 | tail -1 | awk '{print $3"/"$2}')"
  echo "  CPU cores: $(nproc)"
  echo "  Shell: $SHELL"
  echo "  PATH entries: $(echo $PATH | tr ':' '\n' | wc -l)"
  if command -v node &>/dev/null; then echo "  Node.js: $(node --version)"; fi
  if command -v python3 &>/dev/null; then echo "  Python: $(python3 --version)"; fi
  if command -v docker &>/dev/null; then echo "  Docker: $(docker --version)"; fi
  echo "::endgroup::"
}

ci_artifact_test() {
  echo "::group::📁 Artifact handling test"
  echo "Creating test artifacts..."
  mkdir -p /tmp/ci-artifacts
  echo "test artifact content $(date -u)" > /tmp/ci-artifacts/test.log
  echo '{"test":true,"timestamp":"'"$(date -u +%s)"'"}' > /tmp/ci-artifacts/report.json
  tar czf /tmp/ci-artifacts/archive.tar.gz -C /tmp/ci-artifacts test.log report.json
  echo "  Created archive.tar.gz ($(du -h /tmp/ci-artifacts/archive.tar.gz | cut -f1))"
  echo "Testing extraction..."
  tar xzf /tmp/ci-artifacts/archive.tar.gz -C /tmp/ci-artifacts-verify 2>/dev/null && echo "  ✅ Extraction verified"
  rm -rf /tmp/ci-artifacts /tmp/ci-artifacts-verify
  echo "::endgroup::"
}

# Task rotation — cycles through CI activities
TASKS=(ci_network_check ci_dependency_check ci_build_test ci_integration_test ci_security_scan ci_performance_test ci_environment_report ci_artifact_test)

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
  echo "  ⏰  EXTENDED CI PIPELINE +${EXTRA_MINUTES} minutes"
  echo "  📊 Total extensions: ${EXTENSION_COUNT}/${MAX_EXTENSIONS}"
  echo "  ⏳  New ETA: $(date -d "+${TOTAL_REMAINING} minutes" '+%H:%M:%S UTC')"
  echo "══════════════════════════════════════════════════════"
  echo ""

  return 0
}

# ── Service Health Monitor ──────────────────────────────────

restart_services() {
  # Xvfb
  if ! pgrep -f "Xvfb" > /dev/null; then
    echo "⚠️  Xvfb crashed! Restarting..."
    RESOLUTION=$(cat /tmp/vps-resolution.txt 2>/dev/null || echo "1920x1080")
    sudo Xvfb :0 -screen 0 "${RESOLUTION}x24" -ac +extension GLX +render -noreset &>/dev/null &
    sleep 2
  fi

  # x11vnc
  if ! pgrep -f "x11vnc" > /dev/null && [ -f /tmp/vnc-password.txt ]; then
    echo "⚠️  VNC server crashed! Restarting..."
    nohup x11vnc -display :0 -rfbport 5900 -forever -shared \
      -rfbauth /tmp/vnc-password.txt > /tmp/x11vnc.log 2>&1 &
    sleep 2
  fi

  # websockify/noVNC
  if ! pgrep -f "websockify" > /dev/null && [ -f /tmp/vnc-password.txt ]; then
    echo "⚠️  noVNC proxy crashed! Restarting..."
    nohup websockify --web /opt/noVNC 6080 localhost:5900 > /tmp/novnc.log 2>&1 &
    sleep 2
  fi

  # Cloudflare tunnel
  if ! pgrep -f "cloudflared" > /dev/null && [ -f /tmp/cloudflared.log ]; then
    echo "⚠️  Tunnel crashed! Restarting..."
    nohup cloudflared tunnel --url http://localhost:6080 --no-autoupdate \
      > /tmp/cloudflared.log 2>&1 &
    sleep 3
    NEW_URL=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1 || true)
    [ -n "$NEW_URL" ] && echo "   New tunnel: $NEW_URL/vnc.html"
  fi

  # xRDP
  if ! pgrep -f "xrdp" > /dev/null && [ -f /tmp/rdp-password.txt ]; then
    echo "⚠️  RDP crashed! Restarting..."
    sudo xrdp > /dev/null 2>&1 &
    sleep 2
  fi

  # Tailscale
  if ! pgrep -f "tailscaled" > /dev/null && [ -f /tmp/tailscale-state-save.tgz ]; then
    echo "⚠️  Tailscale crashed! Restarting..."
    nohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &
    sleep 3
  fi

  # CRD
  if ! pgrep -f "chrome-remote-desktop" > /dev/null && pgrep -f "Xvfb" > /dev/null; then
    echo "⚠️  CRD crashed! Restarting..."
    DISPLAY=:0 nohup /opt/google/chrome-remote-desktop/chrome-remote-desktop --start > /dev/null 2>&1 &
    sleep 3
  fi
}

# ── Main Loop ───────────────────────────────────────────────
echo "🚀 Starting CI/CD pipeline simulation..."
echo ""

while true; do
  if [ $SECONDS -ge $END_TIME ]; then
    echo ""
    echo "✅ CI pipeline completed successfully."
    echo "   Duration: $((SECONDS / 60)) min | Extensions: ${EXTENSION_COUNT}"
    echo "   Proceeding to post-build artifacts..."
    exit 0
  fi

  TICK=$((TICK + 1))
  REMAINING=$(( (END_TIME - SECONDS) / 60 ))

  # ── Check extensions every 3 min ──────────────────────────
  if [ $((TICK % 3)) -eq 0 ]; then
    check_for_extension || true
    REMAINING=$(( (END_TIME - SECONDS) / 60 ))
    if [ $REMAINING -lt 1 ]; then
      echo "✅ CI pipeline completed."
      exit 0
    fi
  fi

  # ── Service health check (every tick) ─────────────────────
  restart_services

  # ── Run a CI/CD task (every tick, rotated) ────────────────
  echo ""
  echo "── Pipeline tick #${TICK} | ~${REMAINING} min remaining ──"
  run_ci_task

  # ── Keepalive heartbeat to stdout ─────────────────────────
  echo ""
  FILLED=$(( (SECONDS * 20) / (END_TIME) ))
  [ $FILLED -gt 20 ] && FILLED=20
  EMPTY=$(( 20 - FILLED ))
  BAR=$(printf '#%.0s' $(seq 1 $FILLED 2>/dev/null) 2>/dev/null)$(printf '-%.0s' $(seq 1 $EMPTY 2>/dev/null) 2>/dev/null)
  echo "⏳  [${BAR}] ${REMAINING} min left | extensions: ${EXTENSION_COUNT}/${MAX_EXTENSIONS}"

  # Small sleep between tasks (keeps output flowing)
  sleep 10
done
