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
#  11. STG PR routing — feature->main (H10) / main->stg (H11) (hard block,
#      STG_ENABLED=true only). Evaluated BEFORE guard 10 so an executor-wrapped
#      PR is still routed here instead of slipping past guard 10's warning-exit.
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
# Default FALSE: interactive sessions honor H7/H8 (confirm before push / PR) —
# the safe, intuitive default. Unattended runs opt in explicitly through the
# launch command, which already carries SIDEKICK_AUTO=true, so the opt-in is
# coupled to entering unattended mode rather than a hidden toggle a user must
# discover (ADR-0026). Hard blocks (deny) are NEVER auto-approved — they guard
# irreversible damage regardless of AUTO_MODE.
#
# Usage (unattended, full-auto): SIDEKICK_AUTO=true claude --dangerouslySkipPermissions
AUTO_MODE="${SIDEKICK_AUTO:-false}"

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

# --- Guard 4.5: shell write to .env — redirect / cp / mv (hard block, template-aware) [M-1] ---
# Blocks shell writes whose DESTINATION is the exact `.env` basename (redirect
# `>`/`>>`, or a `cp`/`mv` destination). This is the H5 boundary that keeps .env
# pointed at staging. The terminator class [^A-Za-z0-9._-] keeps `.env.example` /
# `.env.local` / `.env-prod` from matching as the destination (only bare `.env`).
#
# Guard 4.5 is the SOLE enforcement for the "repoint .env by copying a file over
# it" vector: Guard 4 only inspects the command TEXT for a literal `DATABASE_URL`
# token, so `cp .env.production .env` / `cat prod.env > .env` / `base64 -d blob >
# .env` carry a production connection string with no such token and slip past
# Guard 4 entirely (verified in the L2 adversarial pass). So this guard must stay
# a HARD block for arbitrary/production sources and for every redirect.
#
# NARROW EXCEPTION (warn, not block): a `cp`/`mv` FROM a placeholder template
# (`.env.example` / `.env.sample` / `.env.template` / `.env.dist`) INTO `.env` —
# the universal first-time-setup step, which carries no real credentials. A hard
# block there was pure friction, so it is downgraded to a WARNING. The exception
# is limited to template SOURCES matched as the copy's source token; it does NOT
# cover redirects or non-template sources (a prod `.env` from another path stays
# blocked). The worktree-guide replication form `cp .env ../<wt>/.env` already
# passes (its dest has a `/` before `.env`, so the destination matcher misses).
#
# PER-SEGMENT evaluation (mirrors Guard 2 / Guard 11): each `;`/`&&`/`||`/`|`
# segment is judged on its own. A whole-command match would let one template copy
# (`cp .env.example .env`) downgrade a co-located prod repoint in the SAME chain
# (`... && cp .env.production .env`) to a mere warning — so the exception is
# scoped to the segment that actually is the template copy; every other .env
# write in the chain is judged independently and still hard-denied. The `#` in
# the cp/mv terminator class closes a trailing-comment bypass (`cp x .env #note`).
#
# DEFERRED emit (flag, not exit) for the template WARNING: a template segment
# sets a flag instead of emitting, so a downstream HARD block in a later segment
# or guard (Guard 5 rm -rf, Guard 6 prisma db push, Guard 7/8 gh, Guard 11 STG)
# still fires first; the warning is emitted only at the very end. A non-template
# .env write denies immediately.
#
# Known pre-existing gaps (present in the original hard-deny too; NOT introduced
# here, backlogged for the guard-fix wave): a trailing fd redirect after the dest
# (`cp x .env 2>/dev/null`), `tee .env`, and `$(...)` command substitution are
# not seen by the destination matchers, so those forms fall through to silent.
ENV_WRITE_WARN=0
while IFS= read -r _eseg; do
  [ -z "$_eseg" ] && continue
  # Does this segment write to the exact `.env` basename (redirect / cp|mv dest)?
  printf '%s\n' "$_eseg" | grep -qE '>>?[[:space:]]*[^[:space:]|&;>]*\.env([^A-Za-z0-9._-]|$)' \
    || printf '%s\n' "$_eseg" | grep -qE '(^|[^[:alnum:]])(cp|mv)[[:space:]].*[[:space:]]\.env[[:space:]]*([#;&|"'"'"'`]|$)' \
    || continue
  # It does. Template-source cp/mv into .env -> warn (deferred); anything else
  # (redirect, non-template source) -> hard deny for THIS segment, immediately.
  # ANCHORED to the whole segment (^…$): the segment must be EXACTLY a template
  # copy and nothing else. A merely-CONTAINED template substring must not
  # vaccinate a prod write sharing the segment via a comment (`cp .env.production
  # .env # cp .env.example .env`) or command substitution (`cp .env.production
  # .env \`cp .env.template .env\``) — those are not a whole-segment template
  # copy, so they fall through to the hard deny.
  if printf '%s\n' "$_eseg" | grep -qE '^[[:space:]]*(cp|mv)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*[^[:space:]]*\.env\.(example|sample|template|dist)[[:space:]]+[^[:space:]]*\.env[[:space:]]*$'; then
    ENV_WRITE_WARN=1
  else
    deny "Writing to .env via shell (redirect / cp / mv) is forbidden — .env must keep pointing at the staging DB. First-time setup: copy from a template (cp .env.example .env) is allowed. Worktree: copy the staging .env forward (cp .env ../<wt>/.env). Production DB work: pass credentials inline (DATABASE_URL=\"prod-string\" node scripts/xxx.js), never by rewriting .env."
  fi
done <<ENV_SEG_EOF
$(printf '%s\n' "$DESTRUCT_CMD" | sed -E 's/(&&|\|\|)/\n/g; s/[;&|]/\n/g')
ENV_SEG_EOF

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

# --- Guard 11: STG PR routing — H10/H11 (active ONLY when STG_ENABLED=true) ---
# H10: feature/* -> main PRs are forbidden (two-stage flow: feature ->
#      release/stg -> main).
# H11: main -> release/stg sync PRs are forbidden (reverse-flow sync).
# Route interpretation (git-strategy.md route table): release/stg -> main is
# the legitimate release path and is deliberately NOT denied here; hotfix/* ->
# main is also allowed. Only the two forbidden routes above are blocked.
#
# ORDERING: this deny-only guard runs BEFORE Guard 10's executor warning (which
# exits), so an executor-wrapped PR (`bash -c "gh pr create --base main ..."`)
# is still evaluated instead of slipping past on the warning's exit 0. Routes
# that are not forbidden fall through to Guard 10 unchanged.
#
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
# Normalise: strip quotes so a quoted YAML value (`STG_ENABLED: "true"`) is
# recognised instead of silently no-opping the routing guard.
STG_ENABLED_VAL=$(printf '%s' "$STG_ENABLED_VAL" | sed "s/[\"']//g")

# Deny one `gh pr create` invocation if it takes a forbidden STG route.
# Extracts --base/-B and --head/-H from the RAW string (values may be quoted),
# defaults an omitted --head to the current branch (gh's own default), then
# denies ONLY the two forbidden routes. Deny-only: legit routes return 0.
_stg_pr_route_deny() {
  local raw="$1" _base _head
  _base=$(printf '%s\n' "$raw" | grep -oE '(^|[[:space:]])(--base|-B)(=|[[:space:]]+)["'"'"']?[^"'"'"'[:space:]]+' | head -1 | sed -E 's/^[[:space:]]*(--base|-B)(=|[[:space:]]+)["'"'"']?//')
  _head=$(printf '%s\n' "$raw" | grep -oE '(^|[[:space:]])(--head|-H)(=|[[:space:]]+)["'"'"']?[^"'"'"'[:space:]]+' | head -1 | sed -E 's/^[[:space:]]*(--head|-H)(=|[[:space:]]+)["'"'"']?//')
  if [ -z "$_head" ]; then
    if [ -n "$CWD" ]; then
      _head=$(git -C "$CWD" branch --show-current 2>/dev/null)
    else
      _head=$(git branch --show-current 2>/dev/null)
    fi
  fi
  [ -z "$_base" ] && return 0
  if [ "$_base" = "main" ] && printf '%s\n' "$_head" | grep -qE '^feature/'; then
    deny "H10: feature/* -> main PRs are forbidden (STG_ENABLED=true). Use the two-stage route: feature -> release/stg -> main (git-strategy.md)."
  fi
  if [ "$_base" = "release/stg" ] && [ "$_head" = "main" ]; then
    deny "H11: main -> release/stg sync PRs are forbidden (STG_ENABLED=true). release/stg receives feature/* and hotfix/* only; the release path is release/stg -> main (git-strategy.md)."
  fi
  return 0
}

if [ "$STG_ENABLED_VAL" = "true" ]; then
  # Candidate A — the WHOLE command: exactly preserves the prior single-shot
  # behaviour (gate on CLEAN_CMD so quoted PR bodies never false-fire; extract
  # from the raw COMMAND so quoted --base values survive). Every route the old
  # guard denied is still denied here — this branch alone is a strict superset.
  # The executor clause (raw COMMAND names `gh pr create`) closes the bypass
  # where the payload hides inside the quotes CLEAN_CMD strips.
  if printf '%s\n' "$CLEAN_CMD" | grep -qE 'gh\s+pr\s+create\b' \
     || { [ "$EXECUTOR_PRESENT" -eq 1 ] && printf '%s\n' "$COMMAND" | grep -qE 'gh\s+pr\s+create\b'; }; then
    _stg_pr_route_deny "$COMMAND"
  fi
  # Candidates B.. — each command SEGMENT (split on ; && || newline). The old
  # head-1 extraction only saw the first --base/--head pair, so a chained
  # `... --base release/stg ... && gh pr create --base main ...` slipped its
  # second PR through. Each segment is now evaluated on its own; one forbidden
  # route is enough to deny. Same gate as A (clean form, or executor + raw).
  while IFS= read -r _seg; do
    [ -z "$_seg" ] && continue
    _seg_clean=$(printf '%s\n' "$_seg" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g")
    if printf '%s\n' "$_seg_clean" | grep -qE 'gh\s+pr\s+create\b' \
       || { [ "$EXECUTOR_PRESENT" -eq 1 ] && printf '%s\n' "$_seg" | grep -qE 'gh\s+pr\s+create\b'; }; then
      _stg_pr_route_deny "$_seg"
    fi
  done <<STG_SEG_EOF
$(printf '%s\n' "$COMMAND" | sed -E 's/(&&|\|\|)/\n/g; s/[;&|]/\n/g')
STG_SEG_EOF
fi

# --- Guard 10: shell executor present (warning) [C-2b] ---
# Reached only when no destructive pattern was found inside the executor AND the
# command was not a forbidden STG PR route (Guard 11 above already denied those).
if [ "$EXECUTOR_PRESENT" -eq 1 ]; then
  allow_with_context "WARNING: shell executor (bash -c / sh -c / eval / xargs) detected. Quote-based guards are weakened inside executors; verify the wrapped command performs no destructive action."
fi

# --- Guard 4.5 deferred emit: template -> .env setup copy (WARNING — see Guard 4.5) ---
# Runs last so every HARD block above takes precedence over this advisory.
if [ "$ENV_WRITE_WARN" -eq 1 ]; then
  allow_with_context "WARNING: creating .env from a template (cp .env.example .env) detected — allowed as first-time setup. Confirm the resulting .env points at the STAGING DB, not production. For production DB operations, pass credentials inline instead: DATABASE_URL=\"prod-string\" node scripts/xxx.js"
fi

allow_silent