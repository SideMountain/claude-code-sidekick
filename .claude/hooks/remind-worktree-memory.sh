#!/bin/bash
# =============================================================================
# PostToolUse Hook (Bash): H13 reminder after `git worktree add`
#
# Recognition layer for HARD rule H13: right after a worktree is created, the
# next step MUST be recording it in auto-memory MEMORY.md (Active Work) —
# before .env copy / dependency install (git-strategy.md worktree steps,
# "do not skip step 2"). PostToolUse cannot block, so this hook only reminds.
#
# Fires ONLY when the executed Bash command contains `git worktree add` and
# the command did not visibly fail (git failures print "fatal:"/"error:").
# Everything else: completely silent (no stdout at all). If jq is missing the
# failure check degrades to "assume success" — over-reminding is acceptable
# for a recognition-layer hook, silence is not.
#
# Output: official hook JSON ({"systemMessage": ...}) to stdout — nothing else.
# NOTE: Uses printf instead of echo for JSON piping (echo expands backslashes
#       in Windows paths, breaking jq parsing)
#
# chmod +x .claude/hooks/remind-worktree-memory.sh
# =============================================================================

source "$(dirname "$0")/hook-helpers.sh"

INPUT=$(cat)

COMMAND=""
if command -v jq &>/dev/null; then
  COMMAND=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
fi
if [ -z "$COMMAND" ] && [ -n "$INPUT" ]; then
  # grep fallback (jq missing or failed)
  COMMAND=$(printf '%s\n' "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# Strip quoted strings so commit messages / PR bodies mentioning
# `git worktree add` do not trigger the reminder, then neutralise git global
# options (`git -C <dir> worktree add`) via the shared normalizer.
CLEAN_CMD=$(printf '%s\n' "$COMMAND" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g; s/<<'EOF'.*//; s/<<EOF.*//")
WT_CMD=$(normalize_git_cmd "$CLEAN_CMD")

# Not a worktree creation -> stay silent
printf '%s\n' "$WT_CMD" | grep -qE 'git\s+worktree\s+add\b' || exit 0

# Skip when the command visibly failed: interrupted, or git error output.
# (`git worktree add` failures start with "fatal:" / "error:"; its success
# message "Preparing worktree ..." matches neither.)
if command -v jq &>/dev/null; then
  INTERRUPTED=$(printf '%s\n' "$INPUT" | jq -r '.tool_response.interrupted // false' 2>/dev/null)
  [ "$INTERRUPTED" = "true" ] && exit 0
  RESPONSE_TEXT=$(printf '%s\n' "$INPUT" | jq -r '(.tool_response.stdout // "") + "\n" + (.tool_response.stderr // "")' 2>/dev/null)
  if printf '%s\n' "$RESPONSE_TEXT" | grep -qE '^(fatal|error):'; then
    exit 0
  fi
fi

MSG=$(_json_escape "H13: worktree created — record it in auto-memory MEMORY.md (Active Work: branch, task, impact scope, DB migration Y/N) BEFORE the next step (git-strategy.md step 2, do not skip).")
printf '{"systemMessage":"%s"}\n' "$MSG"
exit 0
