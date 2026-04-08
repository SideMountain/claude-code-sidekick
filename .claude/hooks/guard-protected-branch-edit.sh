#!/bin/bash
# =============================================================================
# PreToolUse Hook (Edit|Write): Block file edits on protected branches
#
# Guards:
#   1. Block ALL file edits on protected branches (main)
#      -> Forces work to happen in feature branches via worktrees
#   2. Block .env DATABASE_URL modifications in ALL environments
#      -> Production DB access must use inline env vars, not .env changes
#
# Exit codes:
#   0 = allow (pass to permission dialog)
#   2 = hard block (reject immediately)
#
# chmod +x .claude/hooks/guard-protected-branch-edit.sh
# =============================================================================

INPUT=$(cat)

# Extract file path
if command -v jq &>/dev/null; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
else
  FILE_PATH=$(echo "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# No file path -> skip
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# --- Guard: .env DATABASE_URL modification (all environments) ---
if echo "$FILE_PATH" | grep -qE '[\\/]\.env$'; then
  if command -v jq &>/dev/null; then
    OLD_STR=$(echo "$INPUT" | jq -r '.tool_input.old_string // ""')
    NEW_STR=$(echo "$INPUT" | jq -r '.tool_input.new_string // ""')
  else
    OLD_STR=$(echo "$INPUT" | grep -o '"old_string"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1)
    NEW_STR=$(echo "$INPUT" | grep -o '"new_string"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1)
  fi
  if echo "$OLD_STR$NEW_STR" | grep -q 'DATABASE_URL'; then
    echo "BLOCKED: Modifying DATABASE_URL in .env is forbidden in all environments." >&2
    echo "  For production DB operations, pass DATABASE_URL as an inline env var:" >&2
    echo "  DATABASE_URL=\"prod-connection-string\" node scripts/xxx.js" >&2
    exit 2
  fi
fi

# Determine branch from the file's git directory (worktree-aware)
FILE_DIR=$(dirname "$FILE_PATH")
BRANCH=$(git -C "$FILE_DIR" branch --show-current 2>/dev/null)

# Not in a git repo -> skip
if [ -z "$BRANCH" ]; then
  exit 0
fi

# Not on a protected branch -> allow
if [ "$BRANCH" != "main" ]; then
  exit 0
fi

# --- Protected branch: block all file edits ---
echo "BLOCKED: File editing on protected branch ($BRANCH) is forbidden." >&2
echo "  File: $FILE_PATH" >&2
echo "  Create a worktree and work on a feature/* or hotfix/* branch instead." >&2
exit 2
