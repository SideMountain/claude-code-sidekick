#!/bin/bash
# =============================================================================
# PreToolUse Hook (Bash): Validate git commit messages
#
# Ensures commit messages contain required fields:
#   - Background (背景): why the change is needed
#   - Changes (対応): what was done to solve it
#   - Affected files (影響): which files/directories changed
#
# Skips --amend commits (modifying existing messages).
#
# Output: JSON (hookSpecificOutput) to stdout, human-readable to stderr
#
# chmod +x .claude/hooks/guard-commit-message.sh
# =============================================================================

source "$(dirname "$0")/hook-helpers.sh"

INPUT=$(cat)

if command -v jq &>/dev/null; then
  COMMAND=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
else
  COMMAND=$(printf '%s\n' "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# Fallback: if jq failed (COMMAND is empty but INPUT exists), use grep
if [ -z "$COMMAND" ] && [ -n "$INPUT" ]; then
  COMMAND=$(printf '%s\n' "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# Only check git commit commands (match at start, allow cd prefix)
if ! printf '%s\n' "$COMMAND" | grep -qE '^\s*(cd\s+[^;&]+[;&]+\s*)?git\s+commit'; then
  allow_silent
fi

# Skip --amend (modifying existing commit)
if printf '%s\n' "$COMMAND" | grep -q '\-\-amend'; then
  allow_silent
fi

# Check for required fields in the commit message
MSG="$COMMAND"
MISSING=""

if ! printf '%s\n' "$MSG" | grep -q '背景'; then
  MISSING="${MISSING}背景(Background) "
fi
if ! printf '%s\n' "$MSG" | grep -q '対応'; then
  MISSING="${MISSING}対応(Changes) "
fi
if ! printf '%s\n' "$MSG" | grep -q '影響'; then
  MISSING="${MISSING}影響(Affected) "
fi

if [ -n "$MISSING" ]; then
  deny "Commit message is missing required fields: [${MISSING}]. Format: Line 1: conventional commits summary (feat:/fix:/etc.), then 背景: Why, 対応: How, 影響: Affected files."
fi

allow_silent