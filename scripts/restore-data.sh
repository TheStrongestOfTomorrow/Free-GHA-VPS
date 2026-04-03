#!/usr/bin/env bash
# ============================================================
#  Free GHA VPS - Restore Persistent Data
#  Tries: GitHub Release → vps-data branch → rclone Google Drive
#  First available source wins
# ============================================================
set -euo pipefail

REPO="${GITHUB_REPOSITORY:?❌ GITHUB_REPOSITORY not set}"
RESTORE_DIR="/tmp/restore-data"
RELEASE_TAG="vps-data"
DATA_BRANCH="vps-data"

mkdir -p "$RESTORE_DIR"
RESTORED=false
RESTORE_SOURCE=""

# ═══════════════════════════════════════════════════════════════
#  METHOD 1: GitHub Release (fastest, up to 2GB)
# ═══════════════════════════════════════════════════════════════
echo "🔍 Checking GitHub Release for saved data..."

RELEASE_DATA=$(curl -s \
  -H "Authorization: token ${GH_TOKEN:-$GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO/releases/tags/$RELEASE_TAG" 2>/dev/null || echo "")

if [ -n "$RELEASE_DATA" ] && echo "$RELEASE_DATA" | jq -e '.assets' > /dev/null 2>&1; then
  # Find the data asset (prefer zst, fallback to gz)
  ASSET_URL=$(echo "$RELEASE_DATA" | jq -r '
    [.assets[] | select(.name == "user-data.tar.zst")] | first // empty
    | .browser_download_url' 2>/dev/null || echo "")

  if [ -z "$ASSET_URL" ]; then
    ASSET_URL=$(echo "$RELEASE_DATA" | jq -r '
      [.assets[] | select(.name | startswith("user-data."))] | first // empty
      | .browser_download_url' 2>/dev/null || echo "")
  fi

  if [ -n "$ASSET_URL" ]; then
    ASSET_NAME=$(echo "$RELEASE_DATA" | jq -r '
      [.assets[] | select(.name | startswith("user-data."))] | first // empty
      | .name' 2>/dev/null || echo "user-data.tar.zst")

    ASSET_SIZE=$(echo "$RELEASE_DATA" | jq -r '
      [.assets[] | select(.name | startswith("user-data."))] | first // empty
      | .size' 2>/dev/null || echo "0")

    echo "   📦 Found release asset: $ASSET_NAME ($(numfmt --to=iec $ASSET_SIZE 2>/dev/null || echo "$ASSET_SIZE bytes"))"
    echo "   ⬇️  Downloading..."

    # Download with progress
    curl -sL -o "/tmp/restore-archive" "$ASSET_URL" && {
      echo "   ✅ Downloaded! Extracting..."

      # Install zstd if needed
      if [[ "$ASSET_NAME" == *.zst ]]; then
        if ! command -v zstd &>/dev/null; then
          sudo apt-get install -y -qq zstd > /dev/null 2>&1
        fi
        zstd -d -f "/tmp/restore-archive" -o "/tmp/restore-archive.tar" 2>/dev/null && \
          tar -xf "/tmp/restore-archive.tar" -C "$RESTORE_DIR" 2>/dev/null
      elif [[ "$ASSET_NAME" == *.gz ]]; then
        tar -xzf "/tmp/restore-archive" -C "$RESTORE_DIR" 2>/dev/null
      else
        tar -xf "/tmp/restore-archive" -C "$RESTORE_DIR" 2>/dev/null
      fi

      RESTORED=true
      RESTORE_SOURCE="GitHub Release"
      echo "   ✅ Data restored from GitHub Release!"
    } || echo "   ⚠️  Download failed, trying next method..."
  fi
fi

if [ "$RESTORED" = "false" ]; then
  echo "   ℹ️  No data in GitHub Release"
fi

# ═══════════════════════════════════════════════════════════════
#  METHOD 2: vps-data branch (fallback, auto-splits)
# ═══════════════════════════════════════════════════════════════
if [ "$RESTORED" = "false" ]; then
  echo "🔍 Checking vps-data branch..."

  git fetch origin "$DATA_BRANCH" 2>/dev/null || {
    echo "   ℹ️  No vps-data branch found"
  }

  if git show "origin/$DATA_BRANCH:split-info.json" 2>/dev/null; then
    # ── Split archive exists ─────────────────────────────────
    SPLIT_INFO=$(git show "origin/$DATA_BRANCH:split-info.json" 2>/dev/null || echo "")
    PART_COUNT=$(echo "$SPLIT_INFO" | jq -r '.parts // 1' 2>/dev/null || echo 1)
    EXT=$(echo "$SPLIT_INFO" | jq -r '.ext // "tar.zst"' 2>/dev/null || echo "tar.zst")

    echo "   📦 Found split archive ($PART_COUNT parts, $EXT)"

    # Download all parts
    COMBINED="/tmp/restore-archive.$EXT"
    for i in $(seq 0 $((PART_COUNT - 1))); do
      PART_NUM=$(printf "%02d" $i)
      PART_FILE="user-data.part-$PART_NUM"
      git show "origin/$DATA_BRANCH:$PART_FILE" 2>/dev/null >> "$COMBINED" || {
        echo "   ⚠️  Missing part $PART_NUM, restore incomplete"
        break
      }
    done

    # Extract
    if [ -f "$COMBINED" ]; then
      echo "   ⬇️  Extracting split archive..."
      if [[ "$EXT" == *.zst ]]; then
        if ! command -v zstd &>/dev/null; then
          sudo apt-get install -y -qq zstd > /dev/null 2>&1
        fi
        zstd -d -f "$COMBINED" -o "/tmp/restore-archive.tar" 2>/dev/null && \
          tar -xf "/tmp/restore-archive.tar" -C "$RESTORE_DIR" 2>/dev/null
      else
        tar -xzf "$COMBINED" -C "$RESTORE_DIR" 2>/dev/null
      fi
      RESTORED=true
      RESTORE_SOURCE="vps-data branch (split)"
      echo "   ✅ Data restored from split archive!"
    fi

  elif git show "origin/$DATA_BRANCH:user-data.tar.zst" 2>/dev/null > /tmp/restore-archive; then
    # ── Single zst file ───────────────────────────────────────
    echo "   📦 Found single archive (zst)"
    if ! command -v zstd &>/dev/null; then
      sudo apt-get install -y -qq zstd > /dev/null 2>&1
    fi
    zstd -d -f /tmp/restore-archive -o /tmp/restore-archive.tar 2>/dev/null && \
      tar -xf /tmp/restore-archive.tar -C "$RESTORE_DIR" 2>/dev/null
    RESTORED=true
    RESTORE_SOURCE="vps-data branch"

  elif git show "origin/$DATA_BRANCH:user-data.tar.gz" 2>/dev/null > /tmp/restore-archive; then
    # ── Single gz file ────────────────────────────────────────
    echo "   📦 Found single archive (gz)"
    tar -xzf /tmp/restore-archive -C "$RESTORE_DIR" 2>/dev/null
    RESTORED=true
    RESTORE_SOURCE="vps-data branch"
  fi

  if [ "$RESTORED" = "true" ]; then
    echo "   ✅ Data restored from $RESTORE_SOURCE!"
  fi
fi

# ═══════════════════════════════════════════════════════════════
#  METHOD 3: Google Drive via rclone (power users)
# ═══════════════════════════════════════════════════════════════
RCLONE_CONFIG_SECRET="${RCLONE_CONFIG:-}"

if [ "$RESTORED" = "false" ] && [ -n "$RCLONE_CONFIG_SECRET" ]; then
  echo "🔍 Checking Google Drive backup..."

  if ! command -v rclone &>/dev/null; then
    curl -s https://rclone.org/install.sh | sudo bash 2>/dev/null || {
      echo "   ⚠️  Failed to install rclone"
    }
  fi

  if command -v rclone &>/dev/null; then
    mkdir -p "$HOME/.config/rclone"
    echo "$RCLONE_CONFIG_SECRET" | base64 -d > "$HOME/.config/rclone/rclone.conf"
    chmod 600 "$HOME/.config/rclone/rclone.conf"

    RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
    RCLONE_PATH="${RCLONE_REMOTE}:Free-GHA-VPS/data"

    # Try to find and download the archive
    LATEST_FILE=$(rclone ls "$RCLONE_PATH" --files-only --sort modtime --order desc 2>/dev/null | head -1 || echo "")

    if [ -n "$LATEST_FILE" ]; then
      echo "   📦 Found: $LATEST_FILE"
      rclone copy "$RCLONE_PATH/$LATEST_FILE" /tmp/ --progress 2>&1 | tail -3

      if [ -f "/tmp/$LATEST_FILE" ]; then
        if [[ "$LATEST_FILE" == *.zst ]]; then
          if ! command -v zstd &>/dev/null; then
            sudo apt-get install -y -qq zstd > /dev/null 2>&1
          fi
          zstd -d -f "/tmp/$LATEST_FILE" -o /tmp/restore-archive.tar 2>/dev/null && \
            tar -xf /tmp/restore-archive.tar -C "$RESTORE_DIR" 2>/dev/null
        elif [[ "$LATEST_FILE" == *.gz ]]; then
          tar -xzf "/tmp/$LATEST_FILE" -C "$RESTORE_DIR" 2>/dev/null
        fi
        RESTORED=true
        RESTORE_SOURCE="Google Drive"
        echo "   ✅ Data restored from Google Drive!"
      fi
    else
      echo "   ℹ️  No data found on Google Drive"
    fi

    rm -f "$HOME/.config/rclone/rclone.conf"
  fi
fi

# ═══════════════════════════════════════════════════════════════
#  Apply Restored Data
# ═══════════════════════════════════════════════════════════════
if [ "$RESTORED" = "true" ]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ✅ DATA RESTORED FROM: $RESTORE_SOURCE"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # List what was restored
  echo "  📁 Restored items:"
  if [ -d "$RESTORE_DIR/home/Desktop" ]; then echo "     ✅ Desktop"; fi
  if [ -d "$RESTORE_DIR/home/Documents" ]; then echo "     ✅ Documents"; fi
  if [ -d "$RESTORE_DIR/home/Downloads" ]; then echo "     ✅ Downloads"; fi
  if [ -d "$RESTORE_DIR/home/.config/google-chrome-remote-desktop" ]; then echo "     ✅ CRD Credentials"; fi
  if [ -f "$RESTORE_DIR/home/.bashrc" ]; then echo "     ✅ Bash config"; fi
  if [ -d "$RESTORE_DIR/home/.ssh" ]; then echo "     ✅ SSH keys"; fi
else
  echo ""
  echo "ℹ️  No previous data found — this is a fresh session."
  echo "   Your data will be saved automatically when the session ends."
fi
