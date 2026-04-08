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
# Design:
#   - CLEAN_CMD: strips quoted strings and HEREDOCs to prevent false positives
#   - Specific guards (Guard 2) run before general guards (Guard 3)
#   - exit 2 = hard block, exit 0 = allow (defer to permission dialog)
#
# chmod +x .claude/hooks/guard-bash.sh
# =============================================================================

INPUT=$(cat)

if command -v jq &>/dev/null; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
  CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
else
  COMMAND=$(echo "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
  CWD=$(echo "$INPUT" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# Strip quoted strings and HEREDOCs to avoid false positives
# e.g., gh pr create --body "...git push..." should not trigger push guard
CLEAN_CMD=$(echo "$COMMAND" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g; s/<<'EOF'.*//; s/<<EOF.*//")

# --- Configuration ---
# Protected branches that cannot be directly pushed to
PROTECTED_BRANCHES="main"

# --- Auto Mode ---
# Set SIDEKICK_AUTO=true to auto-approve warnings (exit 0 guards).
# Hard blocks (exit 2) are NEVER auto-approved — they protect against
# irreversible damage regardless of execution mode.
#
# Usage: SIDEKICK_AUTO=true claude --dangerouslySkipPermissions
AUTO_MODE="${SIDEKICK_AUTO:-true}"

# Detect if running in the main workspace (not a worktree)
# Adjust this pattern to match your project's root directory name
is_main_workspace() {
  # Match the last path component of CWD against the project directory name
  # Override this function or set MAIN_WS_PATTERN env var for your project
  local PATTERN="${MAIN_WS_PATTERN:-}"
  if [ -n "$PATTERN" ]; then
    echo "$CWD" | grep -qE "$PATTERN"
  else
    # Fallback: check if .git/worktrees does NOT exist (i.e., this IS the main repo)
    # In a worktree, .git is a file pointing to the main repo
    [ -d "${CWD}/.git" ] 2>/dev/null
  fi
}

# --- Guard 1: git checkout (blocked in main workspace) ---
# Branch work must use worktrees; file restoration must use git restore
if echo "$CLEAN_CMD" | grep -qE 'git\s+checkout\b'; then
  if is_main_workspace; then
    echo "BLOCKED: git checkout is forbidden in the main workspace." >&2
    echo "  Branch work: use 'git worktree add' to create a worktree." >&2
    echo "  File restore: use 'git restore' instead." >&2
    exit 2
  fi
fi

# --- Guard 2: Direct push to protected branches (hard block) ---
# Build regex pattern from PROTECTED_BRANCHES
BRANCH_PATTERN=$(echo "$PROTECTED_BRANCHES" | tr ' ' '|')
if echo "$CLEAN_CMD" | grep -qE "git\s+push\s+\S+\s+($BRANCH_PATTERN)\s*$"; then
  echo "BLOCKED: Direct push to protected branches ($PROTECTED_BRANCHES) is forbidden. Use PRs." >&2
  exit 2
fi
# Also block refspec format: HEAD:main, feature:main, etc.
if echo "$CLEAN_CMD" | grep -qE "git\s+push\s+\S+\s+\S*:($BRANCH_PATTERN)\s*$"; then
  echo "BLOCKED: Direct push to protected branches ($PROTECTED_BRANCHES) is forbidden. Use PRs." >&2
  exit 2
fi

# --- Guard 3: git push general (warning, defer to permission dialog) ---
if echo "$CLEAN_CMD" | grep -qE 'git\s+push\b'; then
  if [ "$AUTO_MODE" = "true" ]; then
    echo "AUTO: git push auto-approved (SIDEKICK_AUTO=true)." >&2
  else
    echo "WARNING: git push detected. Verify the target branch and changes before proceeding." >&2
  fi
  exit 0
fi

# --- Guard 4: .env DATABASE_URL modification via shell (hard block) ---
if echo "$COMMAND" | grep -qE '(sed|awk|echo.*>|tee)' && echo "$COMMAND" | grep -q 'DATABASE_URL' && echo "$COMMAND" | grep -q '\.env'; then
  echo "BLOCKED: Modifying DATABASE_URL in .env via shell is forbidden." >&2
  echo "  .env must always point to the staging DB." >&2
  echo "  For production DB operations, use inline env vars:" >&2
  echo "  DATABASE_URL=\"prod-string\" node scripts/xxx.js" >&2
  exit 2
fi

# --- Guard 5: rm recursive deletion (hard block) ---
if echo "$CLEAN_CMD" | grep -qE 'rm\s+(-rf|-fr|-r|--recursive)\b|rm\s+-f\s+-r\b|rm\s+-r\s+-f\b'; then
  echo "BLOCKED: Recursive file deletion requires user confirmation." >&2
  echo "  Confirm the target path and reason with the user before executing." >&2
  exit 2
fi

# --- Guard 6: prisma db push (hard block) ---
if echo "$CLEAN_CMD" | grep -qE 'prisma\s+db\s+push'; then
  echo "BLOCKED: 'prisma db push' is forbidden. Use 'prisma migrate dev --name <description>' instead." >&2
  exit 2
fi

# --- Guard 6.5: prisma migrate deploy/dev (warning — H4: no autonomous execution) ---
# NOTE: Even in AUTO_MODE, prisma migrate is NOT auto-approved.
# DB migrations are irreversible and always require human confirmation.
if echo "$CLEAN_CMD" | grep -qE 'prisma\s+migrate\s+(deploy|dev)\b'; then
  echo "WARNING: prisma migrate requires user confirmation (HARD rule H4)." >&2
  echo "  Verify the migration name, target DB, and expected changes before proceeding." >&2
  exit 0
fi

# --- Guard 7: gh api write operations (hard block) ---
# (was Guard 6 before prisma guard was added)
if echo "$CLEAN_CMD" | grep -qE 'gh\s+api\b' && echo "$CLEAN_CMD" | grep -qiE '(-X|--method)\s+(POST|PUT|DELETE|PATCH)'; then
  echo "BLOCKED: gh api write operations require user confirmation." >&2
  echo "  Present the operation details to the user before executing." >&2
  exit 2
fi

# --- Guard 8: gh pr merge (dynamic base branch detection) ---
MERGE_CHECK_CMD=$(echo "$CLEAN_CMD" | sed 's/git\s\+commit\s\+[^;&]*//' | sed 's/gh\s\+pr\s\+create\s\+[^;&]*//')
if echo "$MERGE_CHECK_CMD" | grep -qE 'gh\s+pr\s+merge'; then
  # Try to extract PR number and determine base branch
  PR_NUM=$(echo "$MERGE_CHECK_CMD" | grep -oE 'gh\s+pr\s+merge\s+([0-9]+)' | grep -oE '[0-9]+')
  if [ -n "$PR_NUM" ]; then
    BASE=$(gh pr view "$PR_NUM" --json baseRefName -q '.baseRefName' 2>/dev/null)
    if echo "$PROTECTED_BRANCHES" | grep -qw "$BASE"; then
      echo "BLOCKED: PR #$PR_NUM targets protected branch '$BASE'. Merging to protected branches requires explicit user confirmation." >&2
      exit 2
    fi
  fi
  if [ "$AUTO_MODE" = "true" ]; then
    echo "AUTO: gh pr merge auto-approved (SIDEKICK_AUTO=true)." >&2
  else
    echo "WARNING: gh pr merge detected. Verify the PR number, target branch, and changes." >&2
  fi
  exit 0
fi

exit 0
