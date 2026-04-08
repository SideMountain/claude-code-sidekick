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
# Exit codes:
#   0 = allow
#   2 = hard block (missing required fields)
#
# chmod +x .claude/hooks/guard-commit-message.sh
# =============================================================================

INPUT=$(cat)

if command -v jq &>/dev/null; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
else
  COMMAND=$(echo "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# Only check git commit commands (match at start, allow cd prefix)
if ! echo "$COMMAND" | grep -qE '^\s*(cd\s+[^;&]+[;&]+\s*)?git\s+commit'; then
  exit 0
fi

# Skip --amend (modifying existing commit)
if echo "$COMMAND" | grep -q '\-\-amend'; then
  exit 0
fi

# Check for required fields in the commit message
MSG="$COMMAND"
MISSING=""

if ! echo "$MSG" | grep -q '背景'; then
  MISSING="${MISSING}背景(Background) "
fi
if ! echo "$MSG" | grep -q '対応'; then
  MISSING="${MISSING}対応(Changes) "
fi
if ! echo "$MSG" | grep -q '影響'; then
  MISSING="${MISSING}影響(Affected) "
fi

if [ -n "$MISSING" ]; then
  echo "BLOCKED: Commit message is missing required fields: [${MISSING}]" >&2
  echo "" >&2
  echo "Commit messages must follow this format:" >&2
  echo "  Line 1: conventional commits summary (feat: / fix: / etc.)" >&2
  echo "  背景: Why this change is needed" >&2
  echo "  対応: How it was solved" >&2
  echo "  影響: Affected files/directories" >&2
  exit 2
fi

exit 0
