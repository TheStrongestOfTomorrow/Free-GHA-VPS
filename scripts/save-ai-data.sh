#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Save AI Model Data
#  Saves chat history, model configs, and Ollama modelfiles
#  Uses same 3-tier storage as other workflows
# ============================================================
set -euo pipefail

DATA_BRANCH="${DATA_BRANCH:-ai-data}"
RELEASE_TAG="${RELEASE_TAG:-ai-data}"
RELEASE_NAME="AI Model Data Archive"
REPO="${GITHUB_REPOSITORY:?❌ GITHUB_REPOSITORY not set}"
RUNNER_HOME="/home/runner"
ARCHIVE_DIR="/tmp/ai-archive"
STORAGE="${STORAGE_MODE:-auto}"
TIMESTAMP=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

mkdir -p "$ARCHIVE_DIR"

echo "💾 Saving AI model data..."
echo "   Storage mode: $STORAGE"
echo ""

# ═══════════════════════════════════════════════════════════════
#  STEP 1: Collect AI data
# ═══════════════════════════════════════════════════════════════
echo "📦 Archiving AI model data..."

# Save chat history and AI data
tar -cf "$ARCHIVE_DIR/ai-data.tar" \
  --exclude='*/models/*' \
  --exclude='*/logs/*' \
  --exclude='*.tmp' \
  --exclude='.cache' \
  -C "$RUNNER_HOME" \
  ai-data/ \
  2>/dev/null || true

# Save Ollama modelfiles (small, important for custom models)
if [ -d "$RUNNER_HOME/.ollama" ]; then
  tar -rf "$ARCHIVE_DIR/ai-data.tar" \
    --exclude='*/models/blobs/*' \
    -C "$RUNNER_HOME" \
    .ollama/modelfile/ \
    .ollama/history \
    .ollama/id_ed25519 \
    .ollama/id_ed25519.pub \
    2>/dev/null || true
fi

# Save user config files
tar -rf "$ARCHIVE_DIR/ai-data.tar" \
  -C "$RUNNER_HOME" \
  .bashrc \
  .bash_history \
  .profile \
  .gitconfig \
  .ssh/ \
  2>/dev/null || true

TAR_SIZE=$(stat -f%z "$ARCHIVE_DIR/ai-data.tar" 2>/dev/null || stat -c%s "$ARCHIVE_DIR/ai-data.tar" 2>/dev/null || echo 0)
echo "   Raw archive: $(numfmt --to=iec $TAR_SIZE)"

# ═══════════════════════════════════════════════════════════════
#  STEP 2: Compress with zstd
# ═══════════════════════════════════════════════════════════════
echo "🗜️  Compressing with zstd..."

if ! command -v zstd &>/dev/null; then
  sudo apt-get install -y -qq zstd > /dev/null 2>&1
fi

zstd -f -10 -o "$ARCHIVE_DIR/ai-data.tar.zst" "$ARCHIVE_DIR/ai-data.tar" 2>/dev/null || {
  echo "⚠️  zstd failed, falling back to gzip..."
  gzip -f "$ARCHIVE_DIR/ai-data.tar"
  ARCHIVE_FILE="$ARCHIVE_DIR/ai-data.tar.gz"
  USE_GZIP=true
}

if [ "${USE_GZIP:-false}" = "false" ]; then
  ARCHIVE_FILE="$ARCHIVE_DIR/ai-data.tar.zst"
  rm -f "$ARCHIVE_DIR/ai-data.tar"
fi

ARCHIVE_SIZE=$(stat -f%z "$ARCHIVE_FILE" 2>/dev/null || stat -c%s "$ARCHIVE_FILE" 2>/dev/null || echo 0)
COMPRESSION_RATIO=$(( 100 - (ARCHIVE_SIZE * 100 / (TAR_SIZE > 0 ? TAR_SIZE : 1)) ))
echo "   Compressed: $(numfmt --to=iec $ARCHIVE_SIZE) ($COMPRESSION_RATIO% smaller)"

if [ "${USE_GZIP:-false}" = "true" ]; then
  ARCHIVE_EXT="tar.gz"
else
  ARCHIVE_EXT="tar.zst"
fi

# ═══════════════════════════════════════════════════════════════
#  STEP 3: Upload to GitHub Release (2GB limit)
# ═══════════════════════════════════════════════════════════════
GITHUB_RELEASE_OK=false

if [ "$STORAGE" != "drive-only" ]; then
  echo ""
  echo "📤 Uploading to GitHub Release..."

  RELEASE_LIMIT=$((2 * 1024 * 1024 * 1024))

  if [ "$ARCHIVE_SIZE" -le $RELEASE_LIMIT ]; then
    echo "   Archive fits in single upload"

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
          \"body\": \"🤖 AI model data archive\\n📅 Last saved: $TIMESTAMP\\n📦 Size: $(numfmt --to=iec $ARCHIVE_SIZE)\",
          \"draft\": false,
          \"prerelease\": false
        }")
      RELEASE_ID=$(echo "$RELEASE_RESPONSE" | jq -r '.id')
    fi

    if [ -n "$RELEASE_ID" ] && [ "$RELEASE_ID" != "null" ]; then
      OLD_ASSET_ID=$(curl -s \
        -H "Authorization: token ${GH_TOKEN:-$GITHUB_TOKEN}" \
        "https://api.github.com/repos/$REPO/releases/$RELEASE_ID/assets" \
        | jq -r '.[] | select(.name == "ai-data.'$ARCHIVE_EXT'") | .id' 2>/dev/null || echo "")

      if [ -n "$OLD_ASSET_ID" ] && [ "$OLD_ASSET_ID" != "null" ]; then
        curl -s -X DELETE \
          -H "Authorization: token ${GH_TOKEN:-$GITHUB_TOKEN}" \
          "https://api.github.com/repos/$REPO/releases/assets/$OLD_ASSET_ID" > /dev/null 2>&1 || true
      fi

      UPLOAD_RESULT=$(curl -s -X POST \
        -H "Authorization: token ${GH_TOKEN:-$GITHUB_TOKEN}" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@$ARCHIVE_FILE" \
        "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=ai-data.$ARCHIVE_EXT" 2>&1)

      if echo "$UPLOAD_RESULT" | jq -e '.id' > /dev/null 2>&1; then
        echo "   ✅ Uploaded to GitHub Release!"
        GITHUB_RELEASE_OK=true
      else
        echo "   ⚠️  Release upload failed, falling back to branch..."
      fi
    else
      echo "   ⚠️  Could not create release, falling back to branch..."
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════
#  STEP 3B: Fallback — Push to branch
# ═══════════════════════════════════════════════════════════════
if [ "$GITHUB_RELEASE_OK" = "false" ] && [ "$STORAGE" != "drive-only" ]; then
  echo ""
  echo "📤 Uploading to $DATA_BRANCH branch..."

  git config user.name "AI-Model Bot"
  git config user.email "ai-bot[bot]@users.noreply.github.com"

  BRANCH_LIMIT=$((95 * 1024 * 1024))

  if git ls-remote --heads origin "$DATA_BRANCH" | grep -q "$DATA_BRANCH"; then
    git fetch origin "$DATA_BRANCH"
    git checkout "$DATA_BRANCH"
    git rm -f ai-data.* split-info.json ai-data.part-* 2>/dev/null || true
  else
    git checkout --orphan "$DATA_BRANCH"
    git rm -rf . 2>/dev/null || true
  fi

  if [ "$ARCHIVE_SIZE" -le $BRANCH_LIMIT ]; then
    cp "$ARCHIVE_FILE" ./ai-data.$ARCHIVE_EXT
    git add ai-data.$ARCHIVE_EXT
  else
    echo "   Splitting archive..."
    SPLIT_DIR="$ARCHIVE_DIR/splits"
    mkdir -p "$SPLIT_DIR"
    split -b $BRANCH_LIMIT -d "$ARCHIVE_FILE" "$SPLIT_DIR/ai-data.part-"
    PART_COUNT=$(ls "$SPLIT_DIR"/ai-data.part-* | wc -l)
    cp "$SPLIT_DIR"/* ./
    echo "{\"parts\": $PART_COUNT, \"ext\": \"$ARCHIVE_EXT\", \"timestamp\": \"$TIMESTAMP\"}" > split-info.json
    git add ai-data.part-* split-info.json
  fi

  echo "{\"last_session\": \"$TIMESTAMP\", \"archive_size\": $ARCHIVE_SIZE, \"type\": \"ai-model\", \"model\": \"${AI_MODEL:-ollama}\", \"models\": \"${AI_MODELS:-${AI_MODEL:-ollama}}\"}" > session-info.json
  git add session-info.json

  git commit -m "🤖 AI data — $TIMESTAMP ($(numfmt --to=iec $ARCHIVE_SIZE))" 2>/dev/null || {
    echo "   ℹ️  No changes to save"
    git checkout main 2>/dev/null || git checkout master 2>/dev/null || true
  }

  git push origin "$DATA_BRANCH" 2>/dev/null || \
    git push --force origin "$DATA_BRANCH" 2>/dev/null || true

  git checkout main 2>/dev/null || git checkout master 2>/dev/null || true
  echo "   ✅ Uploaded to $DATA_BRANCH branch"
fi

# ═══════════════════════════════════════════════════════════════
#  STEP 4: Google Drive (if configured)
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
    RCLONE_PATH="${RCLONE_REMOTE}:Free-GHA-VPS/ai-model"

    rclone mkdir "$RCLONE_PATH" 2>/dev/null || true
    rclone copy "$ARCHIVE_FILE" "$RCLONE_PATH/data/" --progress --stats-one-line 2>&1 | tail -3 && \
      echo "   ✅ Backed up to Google Drive!" || \
      echo "   ⚠️  rclone upload failed"

    rm -f "$HOME/.config/rclone/rclone.conf"
  fi
fi

# ═══════════════════════════════════════════════════════════════
#  Summary
# ═══════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  💾 SAVE COMPLETE (AI Model)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  📦 Original:   $(numfmt --to=iec $TAR_SIZE)"
echo "  🗜️  Compressed: $(numfmt --to=iec $ARCHIVE_SIZE) ($COMPRESSION_RATIO% smaller)"
echo "  📤 GitHub Release: $([ "$GITHUB_RELEASE_OK" = "true" ] && echo "✅" || echo "⚠️  skipped")"
echo "  ☁️  Google Drive:  $([ -n "$RCLONE_CONFIG_SECRET" ] && echo "✅" || echo "not configured")"
echo "  📅 Time: $TIMESTAMP"
echo "  🤖 Model: ${AI_MODEL:-ollama}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
