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

# Fail-closed bootstrap (Issue #103 / ADR-0032): an enforcement guard that
# cannot fully load its helper library must DENY, not silently allow. The load
# runs inside a subshell probe first, so a top-level `exit` or a syntax error in
# the library cannot terminate this guard before the check (a non-zero guard
# exit is a non-blocking hook error = fail-open). The EOF sentinel proves the
# WHOLE file parsed; `unset` + the subshell isolate an env-inherited sentinel.
# Sealing the load-failure hole only — a loaded-but-tampered library is a
# separate trust boundary (ADR-0032), so the deny reason names no file to "fix".
_ccs_helpers="$(dirname "$0")/hook-helpers.sh"
if ! ( unset _CCS_HELPERS_LOADED; . "$_ccs_helpers" >/dev/null 2>&1; [ "${_CCS_HELPERS_LOADED:-}" = "1" ]; ); then
  cat >/dev/null 2>&1 || true
  printf '%s\n' "BLOCKED: enforcement helper library failed to load (fail-closed). Escalate to a human to restore the guards." >&2
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Guard bootstrap failed: the enforcement helper library did not load cleanly. Guards are fail-closed, so this call is blocked. Restoring the enforcement layer is a human step — do not bypass or rewrite the guards to proceed."}}\n'
  exit 0
fi
unset _CCS_HELPERS_LOADED
. "$_ccs_helpers"

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

# --- Gitignored files never reach the protected branch -> allow ---
# The H12/H9 rule this guard enforces ("no direct edits on a protected branch")
# exists so protected-branch history is only touched via PRs. A git-ignored file
# is never committed, so editing it on a protected branch cannot pollute that
# history — and blocking it only creates friction for the personal/local files
# that legitimately live at the repo root and are edited from the main checkout
# (CLAUDE.local.md, .claude/settings.local.json, etc.). .env is exempt from this
# relaxation: the DATABASE_URL guard ABOVE already fired for it and is unaffected
# by ignore status. check-ignore is worktree-aware via `-C` on the file's dir;
# any error (not a repo, git missing) fails safe to the deny below.
if git -C "$FILE_DIR" check-ignore -q "$FILE_PATH" 2>/dev/null; then
  allow_silent
fi

# --- Protected branch: block all file edits ---
deny "File editing on protected branch ($BRANCH) is forbidden. File: $FILE_PATH. Create a worktree and work on a feature/* or hotfix/* branch instead."