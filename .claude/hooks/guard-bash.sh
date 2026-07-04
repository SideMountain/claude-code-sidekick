#!/bin/bash
# =============================================================================
# PreToolUse Hook (Bash): Block dangerous bash commands
#
# Guards:
#   1. git checkout / switch (blocked in main workspace — use worktrees instead)
#   2. git push to protected branches (hard block — must use PRs)
#   3. git push general (warning — defers to permission dialog)
#   4. .env DATABASE_URL modification via shell commands (hard block)
#   4.5 any shell write to .env — redirect / cp / mv (hard block)
#   5. rm recursive deletion (hard block — requires user confirmation)
#   6. prisma db push (hard block — must use prisma migrate dev)
#   7. gh api write operations (hard block — POST/PUT/DELETE/PATCH)
#   8. gh pr merge (warning — defers to permission dialog)
#   9. find bulk deletion (-delete / -exec rm) (warning)
#  10. shell executor present (bash -c / sh -c / eval / xargs) (warning)
#
# Guard hardening (red-team): git invocations are normalised first so that
# `git -C <dir>` / `-c` / `--git-dir` cannot smuggle a subcommand past a guard
# (normalize_git_cmd). Destructive guards additionally inspect the raw command
# when a shell executor is present, because executors carry their payload inside
# the quotes that CLEAN_CMD strips.
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

# --- Normalization & executor detection (guard hardening) ---
# C-1: neutralise `git -C <dir>` / `-c` / `--git-dir` / `--work-tree` so the git
#      guards see the real subcommand instead of skipping over a leading option.
GIT_CMD=$(normalize_git_cmd "$CLEAN_CMD")

# C-2: shell executors (bash -c / sh -c / eval / xargs) carry their payload
#      inside the quotes that CLEAN_CMD strips, defeating the quote-based
#      defence. When one is present we ALSO inspect the raw COMMAND for
#      destructive patterns so the wrapped payload cannot hide. A harmless
#      executor only triggers a warning (Guard 10), never a deny.
EXECUTOR_PRESENT=0
if printf '%s\n' "$COMMAND" | grep -qE '\b(bash|sh)[[:space:]]+-c\b|\beval\b|\bxargs\b'; then
  EXECUTOR_PRESENT=1
fi

# Haystacks for destructive checks. Default: quote-stripped CLEAN_CMD (avoids
# false positives from quoted text). With an executor present, append the raw
# COMMAND / its git-normalised form so the hidden payload is matched too.
DESTRUCT_CMD="$CLEAN_CMD"
GIT_CHECK_CMD="$GIT_CMD"
if [ "$EXECUTOR_PRESENT" -eq 1 ]; then
  DESTRUCT_CMD=$(printf '%s\n%s' "$CLEAN_CMD" "$COMMAND")
  GIT_CHECK_CMD=$(printf '%s\n%s' "$GIT_CMD" "$(normalize_git_cmd "$COMMAND")")
fi

# --- Guard 1: git checkout / switch (blocked in main workspace) [C-1, L-1] ---
if printf '%s\n' "$GIT_CHECK_CMD" | grep -qE 'git\s+(checkout|switch)\b'; then
  if is_main_workspace; then
    deny "git checkout/switch is forbidden in the main workspace. Use 'git worktree add' for branch work or 'git restore' for file restoration."
  fi
fi

# --- Guard 2: Direct push to protected branches (hard block) [H-1, C-1, C-2] ---
# Token-based: any refspec whose target is a protected branch is blocked,
# regardless of trailing flags/tokens or `$`-anchoring (H-1). Each command
# segment is scanned independently so chained pushes are all covered.
if printf '%s\n' "$GIT_CHECK_CMD" | grep -qE 'git\s+push\b'; then
  while IFS= read -r _seg; do
    printf '%s\n' "$_seg" | grep -qE 'git\s+push\b' || continue
    _push_args=$(printf '%s\n' "$_seg" | sed -E 's/^.*git[[:space:]]+push[[:space:]]*//')
    if push_targets_protected_branch "$_push_args" "$PROTECTED_BRANCHES"; then
      deny "Direct push to protected branches ($PROTECTED_BRANCHES) is forbidden. Use PRs."
    fi
  done <<SEGMENTS_EOF
$(printf '%s\n' "$GIT_CHECK_CMD" | sed -E 's/(&&|\|\|)/\n/g; s/[;&|]/\n/g')
SEGMENTS_EOF
fi

# --- Guard 3: git push general (allow with context) ---
if printf '%s\n' "$GIT_CHECK_CMD" | grep -qE 'git\s+push\b'; then
  if [ "$AUTO_MODE" = "true" ]; then
    allow_with_context "AUTO: git push auto-approved (SIDEKICK_AUTO=true)."
  else
    allow_with_context "WARNING: git push detected. Verify the target branch and changes before proceeding."
  fi
fi

# --- Guard 4: .env DATABASE_URL modification via shell (hard block) [M-1] ---
if printf '%s\n' "$COMMAND" | grep -qE '(sed|awk|echo.*>|printf.*>|tee)' && printf '%s\n' "$COMMAND" | grep -q 'DATABASE_URL' && printf '%s\n' "$COMMAND" | grep -q '\.env'; then
  deny "Modifying DATABASE_URL in .env via shell is forbidden. .env must always point to the staging DB. For production DB operations, use inline env vars: DATABASE_URL=\"prod-string\" node scripts/xxx.js"
fi

# --- Guard 4.5: Any shell write to .env — redirect / cp / mv (hard block) [M-1] ---
# The terminator class [^A-Za-z0-9._-] keeps `.env.example` / `.env.local` /
# `.env-prod` from matching (only the exact `.env` basename is protected).
if printf '%s\n' "$DESTRUCT_CMD" | grep -qE '>>?[[:space:]]*[^[:space:]|&;>]*\.env([^A-Za-z0-9._-]|$)' \
   || printf '%s\n' "$DESTRUCT_CMD" | grep -qE '(^|[^[:alnum:]])(cp|mv)[[:space:]].*[[:space:]]\.env[[:space:]]*([;&|"'"'"'`]|$)'; then
  deny "Writing to .env via shell (redirect / cp / mv) is forbidden. .env is protected and must always point to the staging DB. Edit .env manually, or pass production credentials inline: DATABASE_URL=\"prod-string\" node scripts/xxx.js"
fi

# --- Guard 5: rm recursive deletion (hard block) [H-2: -r/-R + combined flags] ---
if printf '%s\n' "$DESTRUCT_CMD" | grep -qE '\brm\s+(-[a-zA-Z]*[rR]|--recursive)|\brm\s+-[a-zA-Z]*\s+-[a-zA-Z]*[rR]'; then
  deny "Recursive file deletion requires user confirmation. Confirm the target path and reason with the user before executing."
fi

# --- Guard 6: prisma db push (hard block) ---
if printf '%s\n' "$DESTRUCT_CMD" | grep -qE 'prisma\s+db\s+push'; then
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

# --- Guard 9: find bulk deletion (warning) [H-2] ---
# find ... -exec rm -rf already denies via Guard 5; this catches the softer
# forms (-delete / -exec rm without recursion) that still remove many files.
if printf '%s\n' "$DESTRUCT_CMD" | grep -qE '\bfind\b.*-delete\b' \
   || printf '%s\n' "$DESTRUCT_CMD" | grep -qE '\bfind\b.*-exec\s+rm\b'; then
  allow_with_context "WARNING: bulk deletion via find (-delete / -exec rm) detected. This can remove many files irreversibly. Verify the path and predicate before proceeding."
fi

# --- Guard 10: shell executor present (warning) [C-2b] ---
# Reached only when no destructive pattern was found inside the executor.
if [ "$EXECUTOR_PRESENT" -eq 1 ]; then
  allow_with_context "WARNING: shell executor (bash -c / sh -c / eval / xargs) detected. Quote-based guards are weakened inside executors; verify the wrapped command performs no destructive action."
fi

# --- Guard 11: STG PR routing — H10/H11 (active ONLY when STG_ENABLED=true) ---
# H10: feature/* -> main PRs are forbidden (two-stage flow: feature ->
#      release/stg -> main).
# H11: main -> release/stg sync PRs are forbidden (reverse-flow sync).
# Route interpretation (git-strategy.md route table): release/stg -> main is
# the legitimate release path and is deliberately NOT denied here; hotfix/* ->
# main is also allowed. Only the two forbidden routes above are blocked.
# STG_ENABLED is resolved locally (hook-helpers.sh is frozen for concurrent
# edits): SIDEKICK_STG_ENABLED env override first (CI / testing), then the
# CLAUDE.md Project Configuration value. Anything other than a clean "true"
# (unset, false, read failure) -> complete no-op (fail-open, the default).
STG_ENABLED_VAL="${SIDEKICK_STG_ENABLED:-}"
if [ -z "$STG_ENABLED_VAL" ]; then
  _stg_claude_md="$(dirname "$0")/../../CLAUDE.md"
  if [ -f "$_stg_claude_md" ]; then
    STG_ENABLED_VAL=$(grep -m1 -E '^[[:space:]]*STG_ENABLED[[:space:]]*:' "$_stg_claude_md" 2>/dev/null | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]#].*//')
  fi
fi
if [ "$STG_ENABLED_VAL" = "true" ] && printf '%s\n' "$CLEAN_CMD" | grep -qE 'gh\s+pr\s+create\b'; then
  # Extract --base/-B and --head/-H from the RAW command: the values may be
  # quoted, and CLEAN_CMD strips quoted strings. `gh pr create` was detected
  # on CLEAN_CMD above precisely to avoid firing on quoted text (PR bodies).
  PR_BASE=$(printf '%s\n' "$COMMAND" | grep -oE '(^|[[:space:]])(--base|-B)(=|[[:space:]]+)["'"'"']?[^"'"'"'[:space:]]+' | head -1 | sed -E 's/^[[:space:]]*(--base|-B)(=|[[:space:]]+)["'"'"']?//')
  PR_HEAD=$(printf '%s\n' "$COMMAND" | grep -oE '(^|[[:space:]])(--head|-H)(=|[[:space:]]+)["'"'"']?[^"'"'"'[:space:]]+' | head -1 | sed -E 's/^[[:space:]]*(--head|-H)(=|[[:space:]]+)["'"'"']?//')
  if [ -z "$PR_HEAD" ]; then
    # --head omitted: gh pr create defaults to the current branch
    if [ -n "$CWD" ]; then
      PR_HEAD=$(git -C "$CWD" branch --show-current 2>/dev/null)
    else
      PR_HEAD=$(git branch --show-current 2>/dev/null)
    fi
  fi
  if [ -n "$PR_BASE" ]; then
    if [ "$PR_BASE" = "main" ] && printf '%s\n' "$PR_HEAD" | grep -qE '^feature/'; then
      deny "H10: feature/* -> main PRs are forbidden (STG_ENABLED=true). Use the two-stage route: feature -> release/stg -> main (git-strategy.md)."
    fi
    if [ "$PR_BASE" = "release/stg" ] && [ "$PR_HEAD" = "main" ]; then
      deny "H11: main -> release/stg sync PRs are forbidden (STG_ENABLED=true). release/stg receives feature/* and hotfix/* only; the release path is release/stg -> main (git-strategy.md)."
    fi
  fi
fi

allow_silent