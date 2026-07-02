#!/bin/bash
# =============================================================================
# PreToolUse Hook (Edit|Write): Block file edits on protected branches
#
# Guards:
#   1. Block ALL file edits on protected branches (from CLAUDE.md PROTECTED_BRANCHES)
#      -> Forces work to happen in feature branches via worktrees
#   2. Block .env DATABASE_URL modifications in ALL environments
#      -> Production DB access must use inline env vars, not .env changes
#
# Output: JSON (hookSpecificOutput) to stdout, human-readable to stderr
#
# chmod +x .claude/hooks/guard-protected-branch-edit.sh
# =============================================================================

source "$(dirname "$0")/hook-helpers.sh"

INPUT=$(cat)

# Extract file path
if command -v jq &>/dev/null; then
  FILE_PATH=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
else
  FILE_PATH=$(printf '%s\n' "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# Fallback: if jq failed (FILE_PATH is empty but INPUT exists), use grep
if [ -z "$FILE_PATH" ] && [ -n "$INPUT" ]; then
  FILE_PATH=$(printf '%s\n' "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# No file path -> skip
if [ -z "$FILE_PATH" ]; then
  allow_silent
fi

# --- Guard: .env DATABASE_URL modification (all environments) ---
if printf '%s\n' "$FILE_PATH" | grep -qE '[\\/]\.env$'; then
  if command -v jq &>/dev/null; then
    OLD_STR=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.old_string // ""' 2>/dev/null)
    NEW_STR=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.new_string // ""' 2>/dev/null)
  else
    OLD_STR=$(printf '%s\n' "$INPUT" | grep -o '"old_string"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1)
    NEW_STR=$(printf '%s\n' "$INPUT" | grep -o '"new_string"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1)
  fi
  if printf '%s\n' "$OLD_STR$NEW_STR" | grep -q 'DATABASE_URL'; then
    deny "Modifying DATABASE_URL in .env is forbidden in all environments. For production DB operations, pass DATABASE_URL as an inline env var: DATABASE_URL=\"prod-connection-string\" node scripts/xxx.js"
  fi
fi

# Determine branch from the file's git directory (worktree-aware)
FILE_DIR=$(dirname "$FILE_PATH")
BRANCH=$(git -C "$FILE_DIR" branch --show-current 2>/dev/null)

# Not in a git repo -> skip
if [ -z "$BRANCH" ]; then
  allow_silent
fi

# Not on a protected branch -> allow
# Protected set sourced from CLAUDE.md (env override / default "main"; see hook-helpers.sh)
PROTECTED_BRANCHES=$(get_protected_branches "$(dirname "$0")/../../CLAUDE.md")
if ! _branch_in_set "$BRANCH" "$PROTECTED_BRANCHES"; then
  allow_silent
fi

# --- Protected branch: block all file edits ---
deny "File editing on protected branch ($BRANCH) is forbidden. File: $FILE_PATH. Create a worktree and work on a feature/* or hotfix/* branch instead."