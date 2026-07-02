#!/bin/bash
# =============================================================================
# PreToolUse Hook (Bash): Block dangerous bash commands
#
# Guards:
#   1. git checkout (blocked in main workspace — use worktrees instead)
#   2. git push to protected branches (hard block — must use PRs)
#   3. git push general (warning — defers to permission dialog)
#   4. .env DATABASE_URL modification via shell commands (hard block)
#   5. rm recursive deletion (hard block — requires user confirmation)
#   6. prisma db push (hard block — must use prisma migrate dev)
#   7. gh api write operations (hard block — POST/PUT/DELETE/PATCH)
#   8. gh pr merge (warning — defers to permission dialog)
#
# Output: JSON (hookSpecificOutput) to stdout, human-readable to stderr
# NOTE: Uses printf instead of echo for JSON piping (echo expands backslashes
#       in Windows paths, breaking jq parsing)
#
# chmod +x .claude/hooks/guard-bash.sh
# =============================================================================

source "$(dirname "$0")/hook-helpers.sh"

INPUT=$(cat)

if command -v jq &>/dev/null; then
  COMMAND=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
  CWD=$(printf '%s\n' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
else
  COMMAND=$(printf '%s\n' "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
  CWD=$(printf '%s\n' "$INPUT" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# Fallback: if jq failed (COMMAND is empty but INPUT exists), use grep
if [ -z "$COMMAND" ] && [ -n "$INPUT" ]; then
  COMMAND=$(printf '%s\n' "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
  CWD=$(printf '%s\n' "$INPUT" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# Strip quoted strings and HEREDOCs to avoid false positives
# e.g., gh pr create --body "...git push..." should not trigger push guard
CLEAN_CMD=$(printf '%s\n' "$COMMAND" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g; s/<<'EOF'.*//; s/<<EOF.*//")

# --- Configuration ---
# Protected branches that cannot be directly pushed to (space-separated).
# Sourced from CLAUDE.md PROTECTED_BRANCHES (SIDEKICK_PROTECTED_BRANCHES env
# override; defaults to "main" when unset). See hook-helpers.sh.
PROTECTED_BRANCHES=$(get_protected_branches "$(dirname "$0")/../../CLAUDE.md")

# --- Auto Mode ---
# Set SIDEKICK_AUTO=true to auto-approve warnings (allow guards).
# Hard blocks (deny) are NEVER auto-approved — they protect against
# irreversible damage regardless of execution mode.
#
# Usage: SIDEKICK_AUTO=true claude --dangerouslySkipPermissions
AUTO_MODE="${SIDEKICK_AUTO:-true}"

# Detect if running in the main workspace (not a worktree)
is_main_workspace() {
  local PATTERN="${MAIN_WS_PATTERN:-}"
  if [ -n "$PATTERN" ]; then
    printf '%s\n' "$CWD" | grep -qE "$PATTERN"
  else
    [ -d "${CWD}/.git" ] 2>/dev/null
  fi
}

# --- Guard 1: git checkout (blocked in main workspace) ---
if printf '%s\n' "$CLEAN_CMD" | grep -qE 'git\s+checkout\b'; then
  if is_main_workspace; then
    deny "git checkout is forbidden in the main workspace. Use 'git worktree add' for branch work or 'git restore' for file restoration."
  fi
fi

# --- Guard 2: Direct push to protected branches (hard block) ---
BRANCH_PATTERN=$(printf '%s\n' "$PROTECTED_BRANCHES" | tr ' ' '|')
if printf '%s\n' "$CLEAN_CMD" | grep -qE "git\s+push\s+\S+\s+($BRANCH_PATTERN)\s*$"; then
  deny "Direct push to protected branches ($PROTECTED_BRANCHES) is forbidden. Use PRs."
fi
if printf '%s\n' "$CLEAN_CMD" | grep -qE "git\s+push\s+\S+\s+\S*:($BRANCH_PATTERN)\s*$"; then
  deny "Direct push to protected branches ($PROTECTED_BRANCHES) is forbidden. Use PRs."
fi

# --- Guard 3: git push general (allow with context) ---
if printf '%s\n' "$CLEAN_CMD" | grep -qE 'git\s+push\b'; then
  if [ "$AUTO_MODE" = "true" ]; then
    allow_with_context "AUTO: git push auto-approved (SIDEKICK_AUTO=true)."
  else
    allow_with_context "WARNING: git push detected. Verify the target branch and changes before proceeding."
  fi
fi

# --- Guard 4: .env DATABASE_URL modification via shell (hard block) ---
if printf '%s\n' "$COMMAND" | grep -qE '(sed|awk|echo.*>|tee)' && printf '%s\n' "$COMMAND" | grep -q 'DATABASE_URL' && printf '%s\n' "$COMMAND" | grep -q '\.env'; then
  deny "Modifying DATABASE_URL in .env via shell is forbidden. .env must always point to the staging DB. For production DB operations, use inline env vars: DATABASE_URL=\"prod-string\" node scripts/xxx.js"
fi

# --- Guard 5: rm recursive deletion (hard block) ---
if printf '%s\n' "$CLEAN_CMD" | grep -qE 'rm\s+(-rf|-fr|-r|--recursive)\b|rm\s+-f\s+-r\b|rm\s+-r\s+-f\b'; then
  deny "Recursive file deletion requires user confirmation. Confirm the target path and reason with the user before executing."
fi

# --- Guard 6: prisma db push (hard block) ---
if printf '%s\n' "$CLEAN_CMD" | grep -qE 'prisma\s+db\s+push'; then
  deny "'prisma db push' is forbidden. Use 'prisma migrate dev --name <description>' instead."
fi

# --- Guard 6.5: prisma migrate deploy/dev (warning — H4: no autonomous execution) ---
if printf '%s\n' "$CLEAN_CMD" | grep -qE 'prisma\s+migrate\s+(deploy|dev)\b'; then
  allow_with_context "WARNING: prisma migrate requires user confirmation (HARD rule H4). Verify the migration name, target DB, and expected changes before proceeding."
fi

# --- Guard 7: gh api write operations (hard block) ---
if printf '%s\n' "$CLEAN_CMD" | grep -qE 'gh\s+api\b' && printf '%s\n' "$CLEAN_CMD" | grep -qiE '(-X|--method)\s+(POST|PUT|DELETE|PATCH)'; then
  deny "gh api write operations require user confirmation. Present the operation details to the user before executing."
fi

# --- Guard 8: gh pr merge (dynamic base branch detection) ---
MERGE_CHECK_CMD=$(printf '%s\n' "$CLEAN_CMD" | sed 's/git\s\+commit\s\+[^;&]*//' | sed 's/gh\s\+pr\s\+create\s\+[^;&]*//')
if printf '%s\n' "$MERGE_CHECK_CMD" | grep -qE 'gh\s+pr\s+merge'; then
  PR_NUM=$(printf '%s\n' "$MERGE_CHECK_CMD" | grep -oE 'gh\s+pr\s+merge\s+([0-9]+)' | grep -oE '[0-9]+')
  if [ -n "$PR_NUM" ]; then
    BASE=$(gh pr view "$PR_NUM" --json baseRefName -q '.baseRefName' 2>/dev/null)
    if _branch_in_set "$BASE" "$PROTECTED_BRANCHES"; then
      deny "PR #$PR_NUM targets protected branch '$BASE'. Merging to protected branches requires explicit user confirmation."
    fi
  fi
  if [ "$AUTO_MODE" = "true" ]; then
    allow_with_context "AUTO: gh pr merge auto-approved (SIDEKICK_AUTO=true)."
  else
    allow_with_context "WARNING: gh pr merge detected. Verify the PR number, target branch, and changes."
  fi
fi

allow_silent