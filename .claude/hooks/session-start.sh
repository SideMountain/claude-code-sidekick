#!/bin/bash
# =============================================================================
# SessionStart Hook: Automated checks at chat session start
#
# Checks:
#   1. Current branch status (protected branch confirmation + auto-pull)
#   2. Uncommitted changes detection
#   3. Active Work display (from MEMORY.md)
#   4. Existing worktree listing
#
# chmod +x .claude/hooks/session-start.sh
# =============================================================================

INPUT=$(cat)
if command -v jq &>/dev/null; then
  CWD=$(printf '%s\n' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
fi
PROJECT_DIR="${CWD:-$(pwd)}"

# MEMORY.md path — adjust per project if needed
# Claude Code stores memory at ~/.claude/projects/<project-slug>/memory/MEMORY.md
MEMORY_DIR="$HOME/.claude/projects"
MEMORY_FILE=""
if [ -d "$MEMORY_DIR" ]; then
  # Find MEMORY.md matching the current project directory
  MEMORY_FILE=$(find "$MEMORY_DIR" -maxdepth 3 -name "MEMORY.md" 2>/dev/null | head -1)
fi

cd "$PROJECT_DIR" 2>/dev/null || exit 0

# --- Configuration ---
# Protected branches: branches that should not be directly committed to
PROTECTED_BRANCHES=("main")

echo "=== SESSION START: Automated Checks ==="
echo ""

# --- [1/4] Branch Status ---
echo "[1/4] Branch status"
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

# --- [2/4] Uncommitted Changes ---
echo ""
echo "[2/4] Uncommitted changes"
CHANGES=$(git status --short 2>/dev/null)
if [ -n "$CHANGES" ]; then
  echo "  WARNING: Uncommitted changes detected:"
  echo "$CHANGES" | head -20 | sed 's/^/    /'
else
  echo "  OK: clean"
fi

# --- [3/4] Active Work ---
echo ""
echo "[3/4] Active Work (parallel work board)"
if [ -n "$MEMORY_FILE" ] && [ -f "$MEMORY_FILE" ]; then
  sed -n '/^## Active Work/,/^## [^A]/p' "$MEMORY_FILE" | head -30 | sed 's/^/  /'
else
  echo "  (MEMORY.md not found)"
fi

# --- [4/4] Existing Worktrees ---
echo ""
echo "[4/4] Existing worktrees"
git worktree list 2>/dev/null | sed 's/^/  /'

echo ""
echo "=== Review the above before starting work ==="
