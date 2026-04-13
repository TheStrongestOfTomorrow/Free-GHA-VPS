#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Setup Web Host
#  Installs Nginx, Node.js, Python — ready to serve anything
#  First run: ~40 sec, cached: ~10 sec
# ============================================================
set -euo pipefail

CACHE_DIR="/tmp/web-cache"
DEBS_DIR="$CACHE_DIR/debs"

mkdir -p "$DEBS_DIR"

echo "🌐 Setting up web host environment..."

# ── Speed up apt ──────────────────────────────────────────────
sudo sed -i 's|^deb http://archive|deb mirror://mirrors.ubuntu.com/mirrors.txt|g' /etc/apt/sources.list 2>/dev/null || true
sudo apt-get update -qq 2>/dev/null

# ── Install essential tools ───────────────────────────────────
echo "📦 Installing base tools..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  curl wget git nano htop jq net-tools unzip zstd \
  > /dev/null 2>&1

# ── Install Nginx (static file server) ───────────────────────
echo "📦 Installing Nginx..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx > /dev/null 2>&1

# ── Install Node.js + npm ────────────────────────────────────
echo "📦 Installing Node.js..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs npm > /dev/null 2>&1

# ── Install Python3 + pip ───────────────────────────────────
echo "📦 Installing Python3..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  python3 python3-pip python3-venv \
  > /dev/null 2>&1

# ── Download cloudflared (for tunneling) ─────────────────────
echo "📦 Downloading cloudflared..."
if [ -f "$DEBS_DIR/cloudflared" ]; then
  echo "   ✅ Using cached cloudflared"
  sudo cp "$DEBS_DIR/cloudflared" /usr/local/bin/cloudflared
  sudo chmod +x /usr/local/bin/cloudflared
else
  if ! command -v cloudflared &>/dev/null; then
    wget -q -O "$DEBS_DIR/cloudflared" \
      https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
    sudo cp "$DEBS_DIR/cloudflared" /usr/local/bin/cloudflared
    sudo chmod +x /usr/local/bin/cloudflared
  fi
fi

# ── Configure Nginx ───────────────────────────────────────────
echo "⚙️  Configuring Nginx..."
sudo tee /etc/nginx/sites-available/web-host > /dev/null <<'NGINX_EOF'
server {
    listen 8080 default_server;
    listen [::]:8080 default_server;
    server_name _;
    root /var/www/html;
    index index.html index.htm index.php;

    location / {
        try_files $uri $uri/ =404;
        autoindex on;
    }

    # Allow large file uploads
    client_max_body_size 100M;
}
NGINX_EOF

# Remove default site, enable ours
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/web-host /etc/nginx/sites-enabled/web-host 2>/dev/null || true

# ── Set up web root ──────────────────────────────────────────
sudo mkdir -p /var/www/html
sudo chown -R runner:runner /var/www/html

# ── Create default index page ────────────────────────────────
if [ ! -f /var/www/html/index.html ]; then
  sudo tee /var/www/html/index.html > /dev/null <<'HTML_EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Free Web Host - Your Site Here!</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #0d1117; color: #c9d1d9; }
        .container { text-align: center; padding: 2rem; }
        h1 { color: #58a6ff; }
        p { color: #8b949e; max-width: 500px; }
        a { color: #58a6ff; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌐 Free Web Host</h1>
        <p>This is the default page. Replace <code>/var/www/html/index.html</code> with your own files, or clone a repo to get started!</p>
        <p>Powered by <a href="https://github.com/TheStrongestOfTomorrow/Free-GHA-VPS">Free GHA VPS</a></p>
    </div>
</body>
</html>
HTML_EOF
fi

# ── Finished ──────────────────────────────────────────────────
echo ""
echo "✅ Web host setup complete!"
echo "   Nginx:   $(nginx -v 2>&1)"
echo "   Node.js: $(node --version 2>/dev/null || echo 'installed')"
echo "   Python:  $(python3 --version 2>/dev/null)"
echo "   Web root: /var/www/html"
