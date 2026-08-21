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
#   8. Enforcement layer health (fail-closed guards + DB-pattern drift, ADR-0032)
#
# chmod +x .claude/hooks/session-start.sh
# =============================================================================

# Advisory hook — source fail-open (ADR-0032). The enforcement guards are
# fail-closed; this hook must still run (and SURFACE the failure in [9/9]) even
# when the helper library is broken, so it degrades to safe defaults instead.
. "$(dirname "$0")/hook-helpers.sh" 2>/dev/null
_CCS_ENFORCE_OK=0
[ "${_CCS_HELPERS_LOADED:-}" = "1" ] && _CCS_ENFORCE_OK=1
command -v get_protected_branches >/dev/null 2>&1 || get_protected_branches() { printf 'main'; }
command -v get_db_pattern >/dev/null 2>&1 || get_db_pattern() { printf ''; }

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

# --- [1/9] Branch Status ---
echo "[1/9] Branch status"
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

# --- [2/9] Uncommitted Changes ---
echo ""
echo "[2/9] Uncommitted changes"
CHANGES=$(git status --short 2>/dev/null)
if [ -n "$CHANGES" ]; then
  echo "  WARNING: Uncommitted changes detected:"
  echo "$CHANGES" | head -20 | sed 's/^/    /'
else
  echo "  OK: clean"
fi

# --- [3/9] Active Work ---
echo ""
echo "[3/9] Active Work (parallel work board)"
if [ -n "$MEMORY_FILE" ] && [ -f "$MEMORY_FILE" ]; then
  sed -n '/^## Active Work/,/^## [^A]/p' "$MEMORY_FILE" | head -30 | sed 's/^/  /'
else
  echo "  (MEMORY.md not found)"
fi

# --- [4/9] Existing Worktrees ---
echo ""
echo "[4/9] Existing worktrees"
git worktree list 2>/dev/null | sed 's/^/  /'

# --- [5/9] Maintenance ---
echo ""
echo "[5/9] Maintenance"
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
# --- [6/9] Critical sidekick update pending (ADR-0009 P3) ---
echo "[6/9] Critical sidekick update"
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
# --- [7/9] Personal brain layer health check (ADR-0016) ---
echo "[7/9] Personal brain layer"
PERSONAL_BRAIN="$HOME/.claude/brain/thinking.md"
if [ -f "$PERSONAL_BRAIN" ]; then
  echo "  OK: $PERSONAL_BRAIN"
else
  echo "  WARNING: 個人 brain が未配置: $PERSONAL_BRAIN"
  echo "     → /setup または /adopt-sidekick-update でテンプレートから初期化を提案できます"
  echo "     → 不在のままでも PJ brain は機能しますが、個人横断の判断軸が context に乗りません"
fi

echo ""
# --- [8/9] git hooks wiring (core.hooksPath) ---
# core.hooksPath is per-clone local config: after a fresh clone (or a machine
# switch) the tracked .claude/githooks/ exists but NOTHING fires — the hooks go
# silent without any error. Wiring must be verified as config AND substance
# (the directory with hooks), not either alone.
echo "[8/9] git hooks wiring"
if [ -d "$PROJECT_DIR/.claude/githooks" ]; then
  _HOOKS_PATH=$(git -C "$PROJECT_DIR" config core.hooksPath 2>/dev/null)
  if [ "$_HOOKS_PATH" = ".claude/githooks" ]; then
    echo "  OK: core.hooksPath=.claude/githooks (worktree でも有効)"
  else
    echo "  ⚠️  WARNING: core.hooksPath が未配線（現在: '${_HOOKS_PATH:-unset}'）"
    echo "     → .claude/githooks/ の pre-commit / pre-push が一切起動していません（無エラーで沈黙）"
    echo "     → 修正: git config core.hooksPath .claude/githooks（/setup Step 2d 参照）"
  fi
else
  echo "  INFO: .claude/githooks/ が無い構成（githooks 強制層は未使用）"
fi

echo ""
# --- [9/9] Enforcement layer health (ADR-0032) ---
# The enforcement guards are fail-closed on a broken helper library: if it does
# not load, EVERY Bash/Edit is denied. Surface that here so the cause is visible
# rather than mysterious. Also surface DB-pattern drift ("configured then lost"),
# which silently downgrades PRD-write protection.
echo "[9/9] Enforcement layer"
if [ "$_CCS_ENFORCE_OK" = "1" ]; then
  echo "  OK: guard helper library loaded (guards fail-closed on load failure)"
else
  echo "  ⚠️  WARNING: hook-helpers.sh did not load cleanly."
  echo "     → enforcement guards are FAIL-CLOSED: Bash/Edit calls will be denied until fixed."
  echo "     → run: bash -n .claude/hooks/hook-helpers.sh   (check for a syntax error)"
fi
_PRD_PATTERN=$(get_db_pattern "$PROJECT_DIR/CLAUDE.md" PRD_DB_PATTERN 2>/dev/null)
if [ -n "$_PRD_PATTERN" ]; then
  echo "  OK: PRD DB-pattern configured (PRD-write guard active)"
else
  echo "  INFO: no PRD_DB_PATTERN set — PRD-write deny is inactive (expected if this project has no PRD DB)."
fi

echo ""
echo "=== Review the above before starting work ==="
