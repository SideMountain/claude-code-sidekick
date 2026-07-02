#!/bin/bash
# =============================================================================
# SessionStart Hook: Automated checks at chat session start
#
# Checks:
#   1. Current branch status (protected branch confirmation + auto-pull)
#   2. Uncommitted changes detection
#   3. Active Work display (from MEMORY.md)
#   4. Existing worktree listing
#   5. Weekly review staleness check
#   6. Critical sidekick update pending warning (P3, ADR-0009)
#   7. Personal brain layer health check (ADR-0016)
#
# chmod +x .claude/hooks/session-start.sh
# =============================================================================

source "$(dirname "$0")/hook-helpers.sh"

INPUT=$(cat)
if command -v jq &>/dev/null; then
  CWD=$(printf '%s\n' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
fi
PROJECT_DIR="${CWD:-$(pwd)}"

# MEMORY.md path — Claude Code stores memory at ~/.claude/projects/<project-slug>/memory/
# project-slug is PROJECT_DIR with '/' replaced by '-' (leading '-' included)
MEMORY_DIR="$HOME/.claude/projects"
PROJECT_SLUG=""
MEM_DIR=""
MEMORY_FILE=""
if [ -n "$PROJECT_DIR" ]; then
  PROJECT_SLUG=$(printf '%s' "$PROJECT_DIR" | sed 's|/|-|g')
  MEM_DIR="$MEMORY_DIR/$PROJECT_SLUG/memory"
  if [ -f "$MEM_DIR/MEMORY.md" ]; then
    MEMORY_FILE="$MEM_DIR/MEMORY.md"
  fi
fi
# Fallback: find any MEMORY.md (for projects with different slug algorithms / symlinks)
if [ -z "$MEMORY_FILE" ] && [ -d "$MEMORY_DIR" ]; then
  MEMORY_FILE=$(find "$MEMORY_DIR" -maxdepth 3 -name "MEMORY.md" 2>/dev/null | head -1)
  [ -z "$MEM_DIR" ] && MEM_DIR=$(dirname "$MEMORY_FILE" 2>/dev/null)
fi

cd "$PROJECT_DIR" 2>/dev/null || exit 0

# --- Configuration ---
# Protected branches sourced from CLAUDE.md PROTECTED_BRANCHES
# (SIDEKICK_PROTECTED_BRANCHES env override; defaults to "main"). See hook-helpers.sh.
read -ra PROTECTED_BRANCHES <<< "$(get_protected_branches "$PROJECT_DIR/CLAUDE.md")"

echo "=== SESSION START: Automated Checks ==="
echo ""

# --- [1/7] Branch Status ---
echo "[1/7] Branch status"
git fetch origin 2>/dev/null
BRANCH=$(git branch --show-current 2>/dev/null)
echo "  Current branch: $BRANCH"

IS_PROTECTED=false
for PB in "${PROTECTED_BRANCHES[@]}"; do
  if [ "$BRANCH" = "$PB" ]; then
    IS_PROTECTED=true
    break
  fi
done

if [ "$IS_PROTECTED" = true ]; then
  # Auto-pull on protected branch (safe — no direct commits allowed)
  BEHIND=$(git rev-list "HEAD..origin/$BRANCH" --count 2>/dev/null)
  if [ "$BEHIND" -gt 0 ] 2>/dev/null; then
    echo "  $BRANCH is $BEHIND commit(s) behind. Auto-pulling..."
    if git pull --ff-only "origin" "$BRANCH" 2>/dev/null; then
      echo "  OK: pull complete"
    else
      echo "  WARNING: pull failed. Please check manually."
    fi
  else
    echo "  OK: up to date"
  fi
else
  echo "  INFO: Not on a protected branch. Ensure this is intentional."
fi

# --- [2/7] Uncommitted Changes ---
echo ""
echo "[2/7] Uncommitted changes"
CHANGES=$(git status --short 2>/dev/null)
if [ -n "$CHANGES" ]; then
  echo "  WARNING: Uncommitted changes detected:"
  echo "$CHANGES" | head -20 | sed 's/^/    /'
else
  echo "  OK: clean"
fi

# --- [3/7] Active Work ---
echo ""
echo "[3/7] Active Work (parallel work board)"
if [ -n "$MEMORY_FILE" ] && [ -f "$MEMORY_FILE" ]; then
  sed -n '/^## Active Work/,/^## [^A]/p' "$MEMORY_FILE" | head -30 | sed 's/^/  /'
else
  echo "  (MEMORY.md not found)"
fi

# --- [4/7] Existing Worktrees ---
echo ""
echo "[4/7] Existing worktrees"
git worktree list 2>/dev/null | sed 's/^/  /'

# --- [5/7] Maintenance ---
echo ""
echo "[5/7] Maintenance"
if [ -n "$MEMORY_FILE" ] && [ -f "$MEMORY_FILE" ]; then
  LAST_REVIEW=$(grep -o '最終棚卸し: [0-9-]*' "$MEMORY_FILE" 2>/dev/null | head -1 | sed 's/最終棚卸し: //')
  if [ -n "$LAST_REVIEW" ]; then
    # Calculate days since last review (portable across Linux/macOS)
    LAST_EPOCH=$(date -d "$LAST_REVIEW" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$LAST_REVIEW" +%s 2>/dev/null || printf '0')
    NOW_EPOCH=$(date +%s)
    if [ "$LAST_EPOCH" -gt 0 ] 2>/dev/null; then
      DAYS_AGO=$(( (NOW_EPOCH - LAST_EPOCH) / 86400 ))
      if [ "$DAYS_AGO" -gt 7 ]; then
        echo "  WARNING: Last /weekly-inventory was ${DAYS_AGO} days ago (consider running /weekly-inventory)"
      else
        echo "  OK: Last /weekly-inventory: ${LAST_REVIEW} (${DAYS_AGO} days ago)"
      fi
    else
      echo "  (could not parse last review date)"
    fi
  else
    echo "  INFO: /weekly-inventory has never been run"
  fi
else
  echo "  (MEMORY.md not found — skipping review check)"
fi

echo ""
# --- [6/7] Critical sidekick update pending (ADR-0009 P3) ---
echo "[6/7] Critical sidekick update"
CRITICAL_FLAG=""
if [ -n "$MEM_DIR" ]; then
  CRITICAL_FLAG="$MEM_DIR/project_critical_pending.md"
fi
if [ -n "$CRITICAL_FLAG" ] && [ -f "$CRITICAL_FLAG" ]; then
  VERSION=$(grep -o 'release: v[0-9.]*' "$CRITICAL_FLAG" 2>/dev/null | head -1 | sed 's/release: //')
  echo "  ⚠️  CRITICAL sidekick update pending${VERSION:+ ($VERSION)}"
  echo "     → /adopt-sidekick-update で取り込み推奨（stop hook 等の致命的修正を含む可能性）"
else
  echo "  OK: no critical update pending"
fi

echo ""
# --- [7/7] Personal brain layer health check (ADR-0016) ---
echo "[7/7] Personal brain layer"
PERSONAL_BRAIN="$HOME/.claude/brain/thinking.md"
if [ -f "$PERSONAL_BRAIN" ]; then
  echo "  OK: $PERSONAL_BRAIN"
else
  echo "  WARNING: 個人 brain が未配置: $PERSONAL_BRAIN"
  echo "     → /setup または /adopt-sidekick-update でテンプレートから初期化を提案できます"
  echo "     → 不在のままでも PJ brain は機能しますが、個人横断の判断軸が context に乗りません"
fi

echo ""
echo "=== Review the above before starting work ==="
