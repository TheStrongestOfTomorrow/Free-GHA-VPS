#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Save Persistent Data
#  Tiered storage: zstd compress → GitHub Release (2GB)
#                  → rclone to Google Drive (15GB) if configured
# ============================================================
set -euo pipefail

DATA_BRANCH="${DATA_BRANCH:-vps-data}"
RELEASE_TAG="${RELEASE_TAG:-vps-data}"
RELEASE_NAME="VPS Data Archive"
REPO="${GITHUB_REPOSITORY:?❌ GITHUB_REPOSITORY not set}"
RUNNER_HOME="/home/runner"
ARCHIVE_DIR="/tmp/vps-archive"
STORAGE="${STORAGE_MODE:-auto}"
TIMESTAMP=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

mkdir -p "$ARCHIVE_DIR"

echo "💾 Saving persistent data..."
echo "   Storage mode: $STORAGE"
echo ""

# ═══════════════════════════════════════════════════════════════
#  Helper: upload files to data branch (defined BEFORE use)
# ═══════════════════════════════════════════════════════════════
upload_to_branch() {
  local SOURCE="$1"
  local MODE="$2"

  git config user.name "VPS Bot"
  git config user.email "vps-bot[bot]@users.noreply.github.com"

  if git ls-remote --heads origin "$DATA_BRANCH" | grep -q "$DATA_BRANCH"; then
    git fetch origin "$DATA_BRANCH"
    git checkout "$DATA_BRANCH"
    # Remove old data files
    git rm -f user-data.* split-info.json user-data.part-* 2>/dev/null || true
  else
    git checkout --orphan "$DATA_BRANCH"
    git rm -rf . 2>/dev/null || true
  fi

  if [ "$MODE" = "split-upload" ]; then
    cp "$SOURCE"/* ./ 2>/dev/null || true
    git add user-data.part-* split-info.json 2>/dev/null || true
  else
    local FILENAME=$(basename "$SOURCE")
    cp "$SOURCE" "./$FILENAME"
    git add "$FILENAME"
  fi

  # Metadata
  local COMP_TYPE="zstd"
  [ "${USE_GZIP:-false}" = "true" ] && COMP_TYPE="gzip"
  echo "{\"last_session\": \"$TIMESTAMP\", \"archive_size\": $ARCHIVE_SIZE, \"storage\": \"branch\", \"compression\": \"$COMP_TYPE\"}" > session-info.json
  git add session-info.json

  git commit -m "💾 VPS data — $TIMESTAMP ($(numfmt --to=iec $ARCHIVE_SIZE))" 2>/dev/null || {
    echo "   ℹ️  No changes to save"
    git checkout main 2>/dev/null || git checkout master 2>/dev/null || true
    return 0
  }

  git push origin "$DATA_BRANCH" 2>/dev/null || \
    git push --force origin "$DATA_BRANCH" 2>/dev/null || true

  git checkout main 2>/dev/null || git checkout master 2>/dev/null || true
  echo "   ✅ Uploaded to $DATA_BRANCH branch"
}

# ═══════════════════════════════════════════════════════════════
#  STEP 1: Collect user data with smart exclusions
# ═══════════════════════════════════════════════════════════════
echo "📦 Archiving user files..."

tar -cf "$ARCHIVE_DIR/user-data.tar" \
  --exclude='.cache' \
  --exclude='.local/share/Trash' \
  --exclude='.local/share/containers' \
  --exclude='.npm/_cacache' \
  --exclude='.config/google-chrome/Default/Cache' \
  --exclude='.config/google-chrome/Default/Code\ Cache' \
  --exclude='.config/google-chrome/Default/Service\ Worker' \
  --exclude='*.tmp' \
  --exclude='__pycache__' \
  --exclude='node_modules/.cache' \
  --exclude='.vscode-server/data/Machine' \
  -C "$RUNNER_HOME" \
  Desktop/ \
  Documents/ \
  Downloads/ \
  .bashrc \
  .bash_history \
  .profile \
  .ssh/ \
  .gitconfig \
  2>/dev/null || true

# Save CRD credentials separately (critical — always save)
CRD_DIR="$RUNNER_HOME/.config/google-chrome-remote-desktop"
if [ -d "$CRD_DIR" ] && [ -n "$(ls -A "$CRD_DIR" 2>/dev/null)" ]; then
  echo "🔐 Including CRD credentials..."
  tar -rf "$ARCHIVE_DIR/user-data.tar" \
    -C "$RUNNER_HOME/.config" \
    google-chrome-remote-desktop/ 2>/dev/null || true
fi

# Save Tailscale state if available
if [ -f /tmp/tailscale-state-save.tgz ]; then
  echo "🦎 Including Tailscale state..."
  cp /tmp/tailscale-state-save.tgz /tmp/ts-state-tmp.tgz
  tar -rf "$ARCHIVE_DIR/user-data.tar" \
    -C /tmp ts-state-tmp.tgz 2>/dev/null || true
fi

TAR_SIZE=$(stat -f%z "$ARCHIVE_DIR/user-data.tar" 2>/dev/null || stat -c%s "$ARCHIVE_DIR/user-data.tar" 2>/dev/null || echo 0)
echo "   Raw archive: $(numfmt --to=iec $TAR_SIZE)"

# ═══════════════════════════════════════════════════════════════
#  STEP 2: Compress with zstd (~30% smaller than gzip)
# ═══════════════════════════════════════════════════════════════
echo "🗜️  Compressing with zstd..."

# Install zstd if not available
if ! command -v zstd &>/dev/null; then
  sudo apt-get install -y -qq zstd > /dev/null 2>&1
fi

# Compress with zstd level 10 (good balance of speed vs ratio)
zstd -f -10 -o "$ARCHIVE_DIR/user-data.tar.zst" "$ARCHIVE_DIR/user-data.tar" 2>/dev/null || {
  # Fallback to gzip if zstd fails
  echo "⚠️  zstd failed, falling back to gzip..."
  gzip -f "$ARCHIVE_DIR/user-data.tar"
  ARCHIVE_FILE="$ARCHIVE_DIR/user-data.tar.gz"
  USE_GZIP=true
}

if [ "${USE_GZIP:-false}" = "false" ]; then
  ARCHIVE_FILE="$ARCHIVE_DIR/user-data.tar.zst"
  rm -f "$ARCHIVE_DIR/user-data.tar"  # Remove uncompressed tar
fi

ARCHIVE_SIZE=$(stat -f%z "$ARCHIVE_FILE" 2>/dev/null || stat -c%s "$ARCHIVE_FILE" 2>/dev/null || echo 0)
COMPRESSION_RATIO=$(( 100 - (ARCHIVE_SIZE * 100 / (TAR_SIZE > 0 ? TAR_SIZE : 1)) ))
echo "   Compressed: $(numfmt --to=iec $ARCHIVE_SIZE) ($COMPRESSION_RATIO% smaller)"

# Determine file extension
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
  echo "📤 Uploading to GitHub Release (2GB limit)..."

  # 2GB limit for release assets
  RELEASE_LIMIT=$((2 * 1024 * 1024 * 1024))

  if [ "$ARCHIVE_SIZE" -le $RELEASE_LIMIT ]; then
    # ── File fits in one asset — upload directly ──────────────
    echo "   Archive fits in single upload ($(numfmt --to=iec $ARCHIVE_SIZE) < 2GB)"

    # Check if release exists, create or update it
    RELEASE_ID=$(curl -s \
      -H "Authorization: token ${GH_TOKEN:-$GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$REPO/releases/tags/$RELEASE_TAG" \
      | jq -r '.id // empty' 2>/dev/null || echo "")

    if [ -z "$RELEASE_ID" ]; then
      # Create new release
      echo "   Creating release..."
      RELEASE_RESPONSE=$(curl -s -X POST \
        -H "Authorization: token ${GH_TOKEN:-$GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$REPO/releases" \
        -d "{
          \"tag_name\": \"$RELEASE_TAG\",
          \"name\": \"$RELEASE_NAME\",
          \"body\": \"💾 Auto-generated VPS data archive\\n📅 Last saved: $TIMESTAMP\\n📦 Size: $(numfmt --to=iec $ARCHIVE_SIZE)\",
          \"draft\": false,
          \"prerelease\": false
        }")
      RELEASE_ID=$(echo "$RELEASE_RESPONSE" | jq -r '.id')
    fi

    if [ -n "$RELEASE_ID" ] && [ "$RELEASE_ID" != "null" ]; then
      # Delete old asset if it exists
      OLD_ASSET_ID=$(curl -s \
        -H "Authorization: token ${GH_TOKEN:-$GITHUB_TOKEN}" \
        "https://api.github.com/repos/$REPO/releases/$RELEASE_ID/assets" \
        | jq -r '.[] | select(.name == "user-data.'$ARCHIVE_EXT'") | .id' 2>/dev/null || echo "")

      if [ -n "$OLD_ASSET_ID" ] && [ "$OLD_ASSET_ID" != "null" ]; then
        curl -s -X DELETE \
          -H "Authorization: token ${GH_TOKEN:-$GITHUB_TOKEN}" \
          "https://api.github.com/repos/$REPO/releases/assets/$OLD_ASSET_ID" > /dev/null 2>&1 || true
      fi

      # Upload new asset
      UPLOAD_RESULT=$(curl -s -X POST \
        -H "Authorization: token ${GH_TOKEN:-$GITHUB_TOKEN}" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@$ARCHIVE_FILE" \
        "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=user-data.$ARCHIVE_EXT" 2>&1)

      if echo "$UPLOAD_RESULT" | jq -e '.id' > /dev/null 2>&1; then
        echo "   ✅ Uploaded to GitHub Release!"
        GITHUB_RELEASE_OK=true
      else
        echo "   ⚠️  Release upload failed, falling back to branch..."
        echo "   $(echo "$UPLOAD_RESULT" | jq -r '.message // "Unknown error"' 2>/dev/null)"
      fi
    else
      echo "   ⚠️  Could not create release, falling back to branch..."
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════
#  STEP 3B: Fallback — Push to data branch (split if needed)
# ═══════════════════════════════════════════════════════════════

BRANCH_OK=false

if [ "$GITHUB_RELEASE_OK" = "false" ] && [ "$STORAGE" != "drive-only" ]; then
  echo ""
  echo "📤 Uploading to $DATA_BRANCH branch..."

  BRANCH_LIMIT=$((95 * 1024 * 1024))  # 95MB per file (safety margin)

  if [ "$ARCHIVE_SIZE" -le $BRANCH_LIMIT ]; then
    # ── Fits in one file ──────────────────────────────────────
    upload_to_branch "$ARCHIVE_FILE" "user-data.$ARCHIVE_EXT"
  else
    # ── Split into chunks under 95MB ─────────────────────────
    echo "   Archive too large for single file — splitting..."

    SPLIT_DIR="$ARCHIVE_DIR/splits"
    mkdir -p "$SPLIT_DIR"

    split -b $BRANCH_LIMIT -d "$ARCHIVE_FILE" "$SPLIT_DIR/user-data.part-"

    PART_COUNT=$(ls "$SPLIT_DIR"/user-data.part-* | wc -l)
    echo "   Split into $PART_COUNT parts"

    # Save split info
    echo "{\"parts\": $PART_COUNT, \"ext\": \"$ARCHIVE_EXT\", \"timestamp\": \"$TIMESTAMP\"}" > "$SPLIT_DIR/split-info.json"

    upload_to_branch "$SPLIT_DIR" "split-upload"
  fi

  BRANCH_OK=true
fi

# ═══════════════════════════════════════════════════════════════
#  STEP 4: Backup to Google Drive via rclone (if configured)
# ═══════════════════════════════════════════════════════════════

RCLONE_OK=false
RCLONE_CONFIG_SECRET="${RCLONE_CONFIG:-}"

if [ -n "$RCLONE_CONFIG_SECRET" ] && [ "$STORAGE" != "github-only" ]; then
  echo ""
  echo "☁️  Backing up to Google Drive via rclone..."

  # Install rclone
  if ! command -v rclone &>/dev/null; then
    curl -s https://rclone.org/install.sh | sudo bash 2>/dev/null || {
      echo "   ⚠️  Failed to install rclone"
      RCLONE_CONFIG_SECRET=""
    }
  fi

  if command -v rclone &>/dev/null && [ -n "$RCLONE_CONFIG_SECRET" ]; then
    # Decode and write rclone config
    mkdir -p "$HOME/.config/rclone"
    echo "$RCLONE_CONFIG_SECRET" | base64 -d > "$HOME/.config/rclone/rclone.conf"
    chmod 600 "$HOME/.config/rclone/rclone.conf"

    # Create VPS folder on Drive
    RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
    RCLONE_PATH="${RCLONE_REMOTE}:Free-GHA-VPS"

    rclone mkdir "$RCLONE_PATH" 2>/dev/null || true

    # Upload the archive
    if rclone copy "$ARCHIVE_FILE" "$RCLONE_PATH/data/" --progress --stats-one-line 2>&1 | tail -3; then
      echo "   ✅ Backed up to Google Drive!"
      RCLONE_OK=true

      # Save metadata to Drive too
      echo "{\"last_session\": \"$TIMESTAMP\", \"archive_size\": $ARCHIVE_SIZE, \"storage\": \"gdrive\"}" \
        > /tmp/vps-drive-meta.json
      rclone copy /tmp/vps-drive-meta.json "$RCLONE_PATH/" 2>/dev/null || true
    else
      echo "   ⚠️  rclone upload failed — check your RCLONE_CONFIG secret"
    fi

    # Clean up config
    rm -f "$HOME/.config/rclone/rclone.conf"
  fi
fi

# ═══════════════════════════════════════════════════════════════
#  Summary
# ═══════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  💾 SAVE COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  📦 Original:   $(numfmt --to=iec $TAR_SIZE)"
echo "  🗜️  Compressed: $(numfmt --to=iec $ARCHIVE_SIZE) ($COMPRESSION_RATIO% smaller)"
echo "  📤 GitHub Release: $([ "$GITHUB_RELEASE_OK" = "true" ] && echo "✅" || echo "⚠️  skipped")"
echo "  🌿 Branch backup: $([ "$BRANCH_OK" = "true" ] && echo "✅" || echo "n/a")"
echo "  ☁️  Google Drive:  $([ "$RCLONE_OK" = "true" ] && echo "✅" || echo "not configured")"
echo "  📅 Time: $TIMESTAMP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
