#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Save Web Host Data
#  Saves web files + server config to web-data branch
# ============================================================
set -euo pipefail

DATA_BRANCH="${DATA_BRANCH:-web-data}"
RELEASE_TAG="${RELEASE_TAG:-web-data}"
RELEASE_NAME="Web Host Data Archive"
REPO="${GITHUB_REPOSITORY:?❌ GITHUB_REPOSITORY not set}"
ARCHIVE_DIR="/tmp/web-archive"
STORAGE="${STORAGE_MODE:-auto}"
TIMESTAMP=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

mkdir -p "$ARCHIVE_DIR"

echo "💾 Saving web host data..."
echo "   Storage mode: $STORAGE"
echo ""

# ═══════════════════════════════════════════════════════════════
#  STEP 1: Collect web files
# ═══════════════════════════════════════════════════════════════
echo "📦 Archiving web files..."

tar -cf "$ARCHIVE_DIR/web-data.tar" \
  --exclude='web-project/node_modules' \
  --exclude='web-project/.git/objects' \
  --exclude='web-project/.git/logs' \
  --exclude='web-project/__pycache__' \
  --exclude='web-project/.venv' \
  --exclude='web-project/venv' \
  --exclude='*.tmp' \
  --exclude='.cache' \
  -C /var/www \
  html/ 2>/dev/null || true

# Also save the project source if it exists
if [ -d /home/runner/web-project ]; then
  tar -rf "$ARCHIVE_DIR/web-data.tar" \
    --exclude='node_modules' \
    --exclude='.git/objects' \
    --exclude='.git/logs' \
    --exclude='__pycache__' \
    --exclude='.venv' \
    --exclude='venv' \
    -C /home/runner \
    web-project/ 2>/dev/null || true
fi

# Save server config
if [ -f /etc/nginx/sites-available/web-host ]; then
  tar -rf "$ARCHIVE_DIR/web-data.tar" \
    -C /etc/nginx/sites-available \
    web-host 2>/dev/null || true
fi

TAR_SIZE=$(stat -f%z "$ARCHIVE_DIR/web-data.tar" 2>/dev/null || stat -c%s "$ARCHIVE_DIR/web-data.tar" 2>/dev/null || echo 0)
echo "   Raw archive: $(numfmt --to=iec $TAR_SIZE)"

# ═══════════════════════════════════════════════════════════════
#  STEP 2: Compress
# ═══════════════════════════════════════════════════════════════
echo "🗜️  Compressing with zstd..."

if ! command -v zstd &>/dev/null; then
  sudo apt-get install -y -qq zstd > /dev/null 2>&1
fi

zstd -f -10 -o "$ARCHIVE_DIR/web-data.tar.zst" "$ARCHIVE_DIR/web-data.tar" 2>/dev/null || {
  gzip -f "$ARCHIVE_DIR/web-data.tar"
  ARCHIVE_FILE="$ARCHIVE_DIR/web-data.tar.gz"
  USE_GZIP=true
}

if [ "${USE_GZIP:-false}" = "false" ]; then
  ARCHIVE_FILE="$ARCHIVE_DIR/web-data.tar.zst"
  rm -f "$ARCHIVE_DIR/web-data.tar"
fi

ARCHIVE_SIZE=$(stat -f%z "$ARCHIVE_FILE" 2>/dev/null || stat -c%s "$ARCHIVE_FILE" 2>/dev/null || echo 0)
COMPRESSION_RATIO=$(( 100 - (ARCHIVE_SIZE * 100 / (TAR_SIZE > 0 ? TAR_SIZE : 1)) ))
echo "   Compressed: $(numfmt --to=iec $ARCHIVE_SIZE) ($COMPRESSION_RATIO% smaller)"

ARCHIVE_EXT="tar.zst"
[ "${USE_GZIP:-false}" = "true" ] && ARCHIVE_EXT="tar.gz"

# ═══════════════════════════════════════════════════════════════
#  STEP 3: Upload to GitHub Release
# ═══════════════════════════════════════════════════════════════
GITHUB_RELEASE_OK=false

if [ "$STORAGE" != "drive-only" ]; then
  echo ""
  echo "📤 Uploading to GitHub Release..."

  RELEASE_ID=$(curl -s \
    -H "Authorization: token ${GH_TOKEN:-$GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$REPO/releases/tags/$RELEASE_TAG" \
    | jq -r '.id // empty' 2>/dev/null || echo "")

  if [ -z "$RELEASE_ID" ]; then
    echo "   Creating release..."
    RELEASE_RESPONSE=$(curl -s -X POST \
      -H "Authorization: token ${GH_TOKEN:-$GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$REPO/releases" \
      -d "{
        \"tag_name\": \"$RELEASE_TAG\",
        \"name\": \"$RELEASE_NAME\",
        \"body\": \"🌐 Web host data archive\\n📅 Last saved: $TIMESTAMP\\n📦 Size: $(numfmt --to=iec $ARCHIVE_SIZE)\",
        \"draft\": false,
        \"prerelease\": false
      }")
    RELEASE_ID=$(echo "$RELEASE_RESPONSE" | jq -r '.id')
  fi

  if [ -n "$RELEASE_ID" ] && [ "$RELEASE_ID" != "null" ]; then
    OLD_ASSET_ID=$(curl -s \
      -H "Authorization: token ${GH_TOKEN:-$GITHUB_TOKEN}" \
      "https://api.github.com/repos/$REPO/releases/$RELEASE_ID/assets" \
      | jq -r '.[] | select(.name == "web-data.'$ARCHIVE_EXT'") | .id' 2>/dev/null || echo "")

    if [ -n "$OLD_ASSET_ID" ] && [ "$OLD_ASSET_ID" != "null" ]; then
      curl -s -X DELETE \
        -H "Authorization: token ${GH_TOKEN:-$GITHUB_TOKEN}" \
        "https://api.github.com/repos/$REPO/releases/assets/$OLD_ASSET_ID" > /dev/null 2>&1 || true
    fi

    UPLOAD_RESULT=$(curl -s -X POST \
      -H "Authorization: token ${GH_TOKEN:-$GITHUB_TOKEN}" \
      -H "Content-Type: application/octet-stream" \
      --data-binary "@$ARCHIVE_FILE" \
      "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=web-data.$ARCHIVE_EXT" 2>&1)

    if echo "$UPLOAD_RESULT" | jq -e '.id' > /dev/null 2>&1; then
      echo "   ✅ Uploaded to GitHub Release!"
      GITHUB_RELEASE_OK=true
    else
      echo "   ⚠️  Release upload failed, falling back to branch..."
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════
#  STEP 3B: Fallback branch upload
# ═══════════════════════════════════════════════════════════════
if [ "$GITHUB_RELEASE_OK" = "false" ] && [ "$STORAGE" != "drive-only" ]; then
  echo ""
  echo "📤 Uploading to $DATA_BRANCH branch..."

  git config user.name "Web-Host Bot"
  git config user.email "web-bot[bot]@users.noreply.github.com"

  if git ls-remote --heads origin "$DATA_BRANCH" | grep -q "$DATA_BRANCH"; then
    git fetch origin "$DATA_BRANCH"
    git checkout "$DATA_BRANCH"
    git rm -f web-data.* split-info.json web-data.part-* 2>/dev/null || true
  else
    git checkout --orphan "$DATA_BRANCH"
    git rm -rf . 2>/dev/null || true
  fi

  BRANCH_LIMIT=$((95 * 1024 * 1024))

  if [ "$ARCHIVE_SIZE" -le $BRANCH_LIMIT ]; then
    cp "$ARCHIVE_FILE" ./web-data.$ARCHIVE_EXT
    git add web-data.$ARCHIVE_EXT
  else
    SPLIT_DIR="$ARCHIVE_DIR/splits"
    mkdir -p "$SPLIT_DIR"
    split -b $BRANCH_LIMIT -d "$ARCHIVE_FILE" "$SPLIT_DIR/web-data.part-"
    cp "$SPLIT_DIR"/* ./
    PART_COUNT=$(ls "$SPLIT_DIR"/web-data.part-* | wc -l)
    echo "{\"parts\": $PART_COUNT, \"ext\": \"$ARCHIVE_EXT\", \"timestamp\": \"$TIMESTAMP\"}" > split-info.json
    git add web-data.part-* split-info.json
  fi

  echo "{\"last_session\": \"$TIMESTAMP\", \"archive_size\": $ARCHIVE_SIZE, \"type\": \"web-host\"}" > session-info.json
  git add session-info.json

  git commit -m "🌐 Web data — $TIMESTAMP ($(numfmt --to=iec $ARCHIVE_SIZE))" 2>/dev/null || {
    echo "   ℹ️  No changes to save"
    git checkout main 2>/dev/null || git checkout master 2>/dev/null || true
  }

  git push origin "$DATA_BRANCH" 2>/dev/null || \
    git push --force origin "$DATA_BRANCH" 2>/dev/null || true

  git checkout main 2>/dev/null || git checkout master 2>/dev/null || true
  echo "   ✅ Uploaded to $DATA_BRANCH branch"
fi

# ═══════════════════════════════════════════════════════════════
#  Google Drive backup
# ═══════════════════════════════════════════════════════════════
RCLONE_CONFIG_SECRET="${RCLONE_CONFIG:-}"

if [ -n "$RCLONE_CONFIG_SECRET" ] && [ "$STORAGE" != "github-only" ]; then
  echo ""
  echo "☁️  Backing up to Google Drive..."

  if ! command -v rclone &>/dev/null; then
    curl -s https://rclone.org/install.sh | sudo bash 2>/dev/null || true
  fi

  if command -v rclone &>/dev/null; then
    mkdir -p "$HOME/.config/rclone"
    echo "$RCLONE_CONFIG_SECRET" | base64 -d > "$HOME/.config/rclone/rclone.conf"
    chmod 600 "$HOME/.config/rclone/rclone.conf"

    RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
    RCLONE_PATH="${RCLONE_REMOTE}:Free-GHA-VPS/web-host"

    rclone mkdir "$RCLONE_PATH" 2>/dev/null || true
    rclone copy "$ARCHIVE_FILE" "$RCLONE_PATH/data/" --progress --stats-one-line 2>&1 | tail -3 && \
      echo "   ✅ Backed up to Google Drive!" || \
      echo "   ⚠️  rclone upload failed"

    rm -f "$HOME/.config/rclone/rclone.conf"
  fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  💾 SAVE COMPLETE (Web Host)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  📦 Original:   $(numfmt --to=iec $TAR_SIZE)"
echo "  🗜️  Compressed: $(numfmt --to=iec $ARCHIVE_SIZE) ($COMPRESSION_RATIO% smaller)"
echo "  📤 GitHub:  $([ "$GITHUB_RELEASE_OK" = "true" ] && echo "✅" || echo "⚠️")"
echo "  ☁️  Drive:   $([ -n "$RCLONE_CONFIG_SECRET" ] && echo "✅" || echo "n/a")"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
