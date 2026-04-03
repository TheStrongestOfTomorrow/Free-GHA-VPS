#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Start Web Server
#  Auto-detects framework and starts the right server
#
#  Usage: bash start-webhost.sh [server_type] [framework] [port]
#  server_type: auto|nginx|node|python
#  framework:   node|python|static|auto
#  port:        port number (default 8080)
# ============================================================
set -euo pipefail

SERVER_TYPE="${1:-auto}"
FRAMEWORK="${2:-auto}"
PORT="${3:-8080}"

echo "🚀 Starting web server..."

# ── Kill existing servers ─────────────────────────────────────
sudo pkill -f nginx 2>/dev/null || true
sudo pkill -f "node.*server" 2>/dev/null || true
sudo pkill -f "python3 -m http" 2>/dev/null || true
sudo pkill -f "flask run" 2>/dev/null || true
sleep 1

# ── Auto-detect framework ─────────────────────────────────────
if [ "$SERVER_TYPE" = "auto" ] && [ "$FRAMEWORK" != "static" ]; then
  if [ -f /home/runner/web-project/package.json ]; then
    # Check if it has a start script
    if grep -q '"start"' /home/runner/web-project/package.json 2>/dev/null; then
      FRAMEWORK="node"
    elif [ -f /home/runner/web-project/next.config.js ] || [ -f /home/runner/web-project/next.config.mjs ]; then
      FRAMEWORK="node"
    elif [ -f /home/runner/web-project/vite.config.js ] || [ -f /home/runner/web-project/vite.config.ts ]; then
      FRAMEWORK="static"  # Vite builds to static
    else
      # Check if there's a dist/build folder (already built)
      if [ -d /home/runner/web-project/dist ] || [ -d /home/runner/web-project/build ]; then
        FRAMEWORK="static"
      else
        FRAMEWORK="node"
      fi
    fi
  elif [ -f /home/runner/web-project/requirements.txt ] || [ -f /home/runner/web-project/app.py ] || [ -f /home/runner/web-project/manage.py ]; then
    FRAMEWORK="python"
  fi
fi

# ── Override with user choice ─────────────────────────────────
if [ "$SERVER_TYPE" != "auto" ]; then
  case "$SERVER_TYPE" in
    nginx)  FRAMEWORK="static" ;;
    node)   FRAMEWORK="node" ;;
    python) FRAMEWORK="python" ;;
  esac
fi

echo "   Framework detected: $FRAMEWORK"
echo "   Port: $PORT"

# ═══════════════════════════════════════════════════════════════
#  STATIC — Nginx
# ═══════════════════════════════════════════════════════════════
if [ "$FRAMEWORK" = "static" ]; then
  # If there's a Node project with build output, copy it
  if [ -d /home/runner/web-project/dist ]; then
    sudo cp -a /home/runner/web-project/dist/. /var/www/html/ 2>/dev/null || true
  elif [ -d /home/runner/web-project/build ]; then
    sudo cp -a /home/runner/web-project/build/. /var/www/html/ 2>/dev/null || true
  elif [ -d /home/runner/web-project/out ]; then
    sudo cp -a /home/runner/web-project/out/. /var/www/html/ 2>/dev/null || true
  fi

  # Ensure Nginx config has the right port
  sudo sed -i "s/listen 8080/listen ${PORT}/g" /etc/nginx/sites-available/web-host 2>/dev/null || true
  sudo sed -i "s/listen \[::\]:8080/listen \[::\]:${PORT}/g" /etc/nginx/sites-available/web-host 2>/dev/null || true

  sudo nginx -t 2>/dev/null && {
    sudo nginx
    sleep 1
    echo "Nginx (static)" > /tmp/web-server-info.txt
    echo "✅ Nginx started on port $PORT"
  } || {
    echo "❌ Nginx config failed, falling back to Python..."
    FRAMEWORK="python"
  }
fi

# ═══════════════════════════════════════════════════════════════
#  NODE — npm start / next dev / custom
# ═══════════════════════════════════════════════════════════════
if [ "$FRAMEWORK" = "node" ]; then
  cd /home/runner/web-project 2>/dev/null || cd /var/www/html

  # Install deps if needed
  if [ -f package.json ] && [ ! -d node_modules ]; then
    echo "📦 Installing npm packages..."
    npm install --silent 2>/dev/null || true
  fi

  # Start the server
  if grep -q '"start"' package.json 2>/dev/null; then
    echo "🚀 Running npm start..."
    nohup npx --yes serve -s . -l $PORT > /tmp/node-server.log 2>&1 &
  elif [ -f server.js ]; then
    echo "🚀 Running server.js..."
    nohup node server.js > /tmp/node-server.log 2>&1 &
  elif [ -f index.js ]; then
    echo "🚀 Running index.js..."
    nohup node index.js > /tmp/node-server.log 2>&1 &
  else
    # Use serve package for any static content
    echo "🚀 Using serve package..."
    nohup npx --yes serve -s . -l $PORT > /tmp/node-server.log 2>&1 &
  fi

  sleep 3
  echo "Node.js" > /tmp/web-server-info.txt
  echo "✅ Node.js server started on port $PORT"
fi

# ═══════════════════════════════════════════════════════════════
#  PYTHON — Flask / Django / http.server
# ═══════════════════════════════════════════════════════════════
if [ "$FRAMEWORK" = "python" ]; then
  cd /home/runner/web-project 2>/dev/null || cd /var/www/html

  # Django
  if [ -f manage.py ]; then
    echo "🚀 Starting Django server..."
    sudo apt-get install -y -qq python3-django 2>/dev/null || true
    python3 manage.py migrate --run-syncdb 2>/dev/null || true
    nohup python3 manage.py runserver 0.0.0.0:$PORT > /tmp/python-server.log 2>&1 &
  # Flask
  elif [ -f app.py ]; then
    echo "🚀 Starting Flask server..."
    pip3 install flask --quiet 2>/dev/null || true
    nohup python3 app.py > /tmp/python-server.log 2>&1 &
  # FastAPI
  elif [ -f main.py ] && grep -q "fastapi" requirements.txt 2>/dev/null; then
    echo "🚀 Starting FastAPI server..."
    pip3 install fastapi uvicorn --quiet 2>/dev/null || true
    nohup uvicorn main:app --host 0.0.0.0 --port $PORT > /tmp/python-server.log 2>&1 &
  else
    # Fallback: simple Python HTTP server
    echo "🚀 Starting Python HTTP server..."
    nohup python3 -m http.server $PORT --bind 0.0.0.0 > /tmp/python-server.log 2>&1 &
  fi

  sleep 3
  echo "Python" > /tmp/web-server-info.txt
  echo "✅ Python server started on port $PORT"
fi

# ── Verify server is responding ──────────────────────────────
echo "🔍 Checking if server is responding..."
for i in $(seq 1 15); do
  if curl -sf http://localhost:$PORT > /dev/null 2>&1; then
    echo "✅ Web server is responding on port $PORT!"
    SERVER_NAME=$(cat /tmp/web-server-info.txt 2>/dev/null || echo "Unknown")
    echo "WEB_SERVER=${SERVER_NAME}" >> $GITHUB_ENV
    exit 0
  fi
  sleep 1
done

echo "⚠️  Server may not be fully ready. Check logs:"
echo "   /tmp/node-server.log"
echo "   /tmp/python-server.log"
# Still exit 0 — the keepalive will auto-restart if needed
exit 0
