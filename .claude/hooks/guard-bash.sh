#!/bin/bash
# =============================================================================
# PreToolUse Hook (Bash): Block dangerous bash commands
#
# Guards:
#   1. git checkout / switch (blocked in main workspace — use worktrees instead)
#   2. git push to protected branches (hard block — must use PRs)
#   2.5 git push to a branch whose PR is already merged (hard block — the
#       commits would never reach the base branch; fail-closed when gh
#       cannot answer)
#   3. git push general (warning — defers to permission dialog)
#   4. .env DATABASE_URL modification via shell commands (hard block)
#   4.5 any shell write to .env — redirect / cp / mv (hard block)
#   5. rm recursive deletion (hard block — requires user confirmation)
#   5.5 git worktree remove while <target>/node_modules exists (hard block —
#       Windows junction incident: git followed the junction and deleted the
#       main workspace's real node_modules. Unlink the junction first.)
#   5.6 rmdir /s (Windows recursive deletion — rm -rf alternate command)
#       (warning — defers to permission dialog)
#   6. prisma db push (hard block — must use prisma migrate dev)
#   7. gh api write operations (hard block — POST/PUT/DELETE/PATCH)
#   8. gh pr merge (warning — defers to permission dialog)
#   8.5 Supabase CLI destructive operations (hard block — H16/H17/H18) /
#       Supabase CLI migration execution (warning — H19/H20). ORM_TYPE=none
#       (Supabase) projects have no prisma-side guard, so this is the ONLY
#       physical enforcement point for those rules.
#   9. find bulk deletion (-delete / -exec rm) (warning)
#  10. shell executor present (bash -c / sh -c / eval / xargs / cmd /c) (warning)
#  11. STG PR routing — feature->main (H10) / main->stg (H11) (hard block,
#      STG_ENABLED=true only). Evaluated BEFORE guard 10 so an executor-wrapped
#      PR is still routed here instead of slipping past guard 10's warning-exit.
#  12. release PR (--base main) carrying migrations (warning — apply order)
#  13. full test suite / build on a non-release branch (warning — the
#      feature->STG gate is scoped tests + typecheck only; STG_ENABLED=true only)
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
# `cmd /c` (Windows shell executor, also written `cmd //c` from Git Bash) is an
# executor too: its payload lives inside the quotes CLEAN_CMD strips, so e.g.
# `cmd /c "rmdir /s /q <dir>"` would otherwise carry a recursive deletion past
# every quote-based guard (found via Guard 5.6 fault injection).
if printf '%s\n' "$COMMAND" | grep -qE '\b(bash|sh)[[:space:]]+-c\b|\beval\b|\bxargs\b|\bcmd(\.exe)?[[:space:]]+//?[cC]\b'; then
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

# --- Guard 2.5: push to a branch whose PR is already MERGED (hard block) ---
# PR がマージされた後に同じブランチへ push しても、その差分は元 PR に反映されない。
# push 自体は成功しリモートにもコミットが載るため「出したつもりでベースに入っていない」が
# 起きる。規約（push 前に PR 状態を確認する）は守り漏れるので機械で止める。
# 判定は .claude/scripts/check-merged-pr.sh（単一の正・git hook 側からも同じ判定を呼ぶ）。
#
# 判定不能（gh 不在 / 未認証 / API 失敗）は fail-closed で block する。意図的に外すときは
# CONFIRM_PUSH_TO_MERGED=1 を付ける（ゲートを外した事実がコマンド履歴に残る）。
if printf '%s\n' "$GIT_CHECK_CMD" | grep -qE 'git\s+push\b'; then
  _pg_script="$(dirname "$0")/../scripts/check-merged-pr.sh"
  if [ -f "$_pg_script" ]; then
    # push 引数から対象ブランチを解決する（最初の非フラグトークンは remote 名）。
    _pg_args=$(printf '%s\n' "$GIT_CHECK_CMD" | sed -E 's/^.*git[[:space:]]+push[[:space:]]*//')
    _pg_branch=""
    _pg_seen_remote=0
    _pg_restore=0
    case $- in *f*) : ;; *) set -f; _pg_restore=1 ;; esac
    for _pg_tok in $_pg_args; do
      case "$_pg_tok" in -*) continue ;; esac
      _pg_tok="${_pg_tok%%;*}"; _pg_tok="${_pg_tok%%&*}"; _pg_tok="${_pg_tok%%|*}"
      [ -z "$_pg_tok" ] && continue
      if [ "$_pg_seen_remote" -eq 0 ]; then _pg_seen_remote=1; continue; fi
      _pg_branch="${_pg_tok##*:}"
      _pg_branch="${_pg_branch#+}"
      _pg_branch="${_pg_branch#refs/heads/}"
      break
    done
    [ "$_pg_restore" -eq 1 ] && set +f
    # refspec 省略時（git push / git push origin）は cwd の現在ブランチが対象。
    if [ -z "$_pg_branch" ]; then
      _pg_branch=$(git -C "${CWD:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null)
    fi
    # detached HEAD 等でブランチを特定できないときは判定しない（誤 block を作らない）。
    if [ -n "$_pg_branch" ] && [ "$_pg_branch" != "HEAD" ]; then
      bash "$_pg_script" "$_pg_branch"
      _pg_rc=$?
      if [ "$_pg_rc" -eq 1 ]; then
        deny "Branch '$_pg_branch' already has a MERGED pull request. Pushing more commits to it will NOT reach the base branch. Create a new branch from the base and open a new PR. Override (leaves a trace): CONFIRM_PUSH_TO_MERGED=1 git push ..."
      elif [ "$_pg_rc" -eq 2 ]; then
        deny "Could not verify whether '$_pg_branch' already has a MERGED pull request (gh missing, unauthenticated, or API error). Blocked fail-closed. Fix gh (gh auth status), or override: CONFIRM_PUSH_TO_MERGED=1 git push ..."
      fi
    fi
  fi
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

# --- Guard 5.5: git worktree remove with node_modules present (hard block) ---
# Incident (2026-07-23, downstream Windows project): `git worktree remove
# --force` followed a node_modules JUNCTION inside the worktree and deleted the
# real main-workspace node_modules through it. The safe order is mechanical:
# ① unlink the junction (`cmd /c rmdir <wt>\node_modules` — removes the link
# only, never the target) ② verify it is gone ③ then `git worktree remove`.
# This guard enforces that order: if the removal target still contains a
# node_modules entry (junction OR real dir), the removal is denied.
# Unresolvable targets (variables/substitution) are denied too — a destructive
# command the guard cannot inspect is fail-closed, not fail-open.
# Per-segment scan (mirrors Guard 2) so chained removals are all covered.
if printf '%s\n' "$GIT_CHECK_CMD" | grep -qE 'git\s+worktree\s+remove\b'; then
  # Targets are extracted from the RAW command (git-normalised) — CLEAN_CMD
  # strips quoted strings, so a quoted literal path ("../wt") would vanish and
  # falsely register as uninspectable. The gate above stays on the quote-
  # stripped form so PR bodies mentioning the command never trigger this guard.
  while IFS= read -r _wseg; do
    printf '%s\n' "$_wseg" | grep -qE 'git\s+worktree\s+remove\b' || continue
    # Extract the target path: strip through "worktree remove", then drop flags.
    _wt_args=$(printf '%s\n' "$_wseg" | sed -E 's/^.*worktree[[:space:]]+remove[[:space:]]*//')
    _wt_target=""
    for _tok in $_wt_args; do
      case "$_tok" in
        -*) continue ;;
        *) _wt_target="$_tok"; break ;;
      esac
    done
    # Strip surrounding quotes if any survived.
    _wt_target=$(printf '%s' "$_wt_target" | sed "s/^[\"']//; s/[\"']\$//")
    if [ -z "$_wt_target" ] || printf '%s' "$_wt_target" | grep -q '[$`]'; then
      deny "git worktree remove: target path could not be inspected (empty or contains a variable/substitution). This command is destructive and the node_modules-junction check cannot run, so it is blocked fail-closed. Re-run with a literal path, one worktree at a time."
    fi
    # Resolve relative targets against the session cwd.
    case "$_wt_target" in
      /*|[A-Za-z]:*) _wt_abs="$_wt_target" ;;
      *) _wt_abs="${CWD}/${_wt_target}" ;;
    esac
    if [ -e "$_wt_abs/node_modules" ]; then
      _wt_win=$(printf '%s' "$_wt_abs" | sed 's|^/\([a-zA-Z]\)/|\1:/|; s|/|\\\\|g')
      deny "git worktree remove: '$_wt_target/node_modules' still exists. On Windows, worktree removal can follow a node_modules junction and delete the REAL main-workspace node_modules through it (incident 2026-07-23). Safe order: (1) unlink the junction: cmd /c rmdir \"$_wt_win\\node_modules\" (removes the link only) (2) verify it is gone (3) re-run git worktree remove. If node_modules is a real directory here, delete it explicitly first so the removal is a conscious step."
    fi
  done <<WT_SEG_EOF
$(normalize_git_cmd "$COMMAND" | sed -E 's/(&&|\|\|)/\n/g; s/[;&|]/\n/g')
WT_SEG_EOF
fi

# --- Guard 5.6: rmdir /s — Windows recursive deletion (warning) [alternate cmd] ---
# `cmd /c rmdir /s /q <dir>` is the Windows twin of `rm -rf` and previously
# slipped past Guard 5 entirely (alternate-command gap). Warning, not deny:
# rmdir /s does NOT follow junctions (that property makes it the recommended
# cleanup tool), but it is still an irreversible bulk deletion that deserves
# the permission dialog's attention.
if printf '%s\n' "$DESTRUCT_CMD" | grep -qiE '\brmdir\b[^;&|]*[[:space:]]/s\b'; then
  allow_with_context "WARNING: rmdir /s (Windows recursive deletion) detected. This deletes the directory tree irreversibly (junctions are removed as links, not followed). Verify the target path before proceeding."
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

# --- Guard 8.5a: Supabase CLI destructive operations (hard block) [H16/H17/H18] ---
# ORM_TYPE=none (Supabase). supabase db reset: drops ALL data and recreates
# schema. Uses DESTRUCT_CMD so an executor-wrapped invocation cannot hide.
if printf '%s\n' "$DESTRUCT_CMD" | grep -qE 'supabase\s+db\s+reset'; then
  deny "'supabase db reset' is forbidden. It drops all data and recreates the schema. To apply new migrations, use 'supabase db push' instead."
fi
# supabase db push --force: forces destructive schema changes (DROP TABLE/COLUMN)
if printf '%s\n' "$DESTRUCT_CMD" | grep -qE 'supabase\s+db\s+push\s+.*--force'; then
  deny "'supabase db push --force' is forbidden. It may drop tables/columns with data. Use the Expand-Contract pattern for destructive changes (see deploy-strategy.md)."
fi
# supabase migration repair: tampers with migration history
if printf '%s\n' "$DESTRUCT_CMD" | grep -qE 'supabase\s+migration\s+repair'; then
  deny "'supabase migration repair' is forbidden. It modifies migration tracking history. If migration state is inconsistent, consult the user."
fi

# --- Guard 8.5b: Supabase CLI migration execution (warning) [H19/H20] ---
# supabase db push: applies pending migrations to the linked project.
if printf '%s\n' "$DESTRUCT_CMD" | grep -qE 'supabase\s+db\s+push\b'; then
  allow_with_context "WARNING: 'supabase db push' applies migrations to the linked Supabase project. Verify: target project, pending migrations, and expected changes (H19; PRD targets need the full H20 approval package)."
fi
# supabase db execute: runs arbitrary SQL
if printf '%s\n' "$DESTRUCT_CMD" | grep -qE 'supabase\s+db\s+execute\b'; then
  allow_with_context "WARNING: 'supabase db execute' runs SQL directly on the database. Verify: target project and SQL content."
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

# --- Guard 12: release PR carrying migrations (warning) ---
# Trigger: `gh pr create --base main` whose diff contains a migrations/ path.
#
# WHY: deploy-strategy.md states that additive (non-destructive) schema changes
# apply the migration BEFORE the deploy. A release PR that ships code writing to
# a column whose migration has not reached production breaks every write to that
# table until the migration is applied. The rule alone does not prevent this —
# what is missing is a reminder at the moment of creating the release PR.
#
# This is advisory only (never blocks): whether the migration must precede the
# deploy depends on the diff (does the shipped code write the new column?), and
# that judgement belongs to the author, not to a pattern match.
#
# ORDERING: placed after every deny guard so blocks keep precedence, and before
# Guard 10 so this specific advisory supersedes the generic executor warning
# (allow_with_context exits, so only the first warning is emitted).
# Fail-open by design: no git, no repo, or a failed diff -> stay silent.
if printf '%s\n' "$COMMAND" | grep -qE 'gh\s+pr\s+create\b' \
   && printf '%s\n' "$COMMAND" | grep -qE '(^|[[:space:]])--base[[:space:]=]+main([[:space:]]|$)'; then
  _repo_root="$(dirname "$0")/../.."
  _mig_files=$(git -C "$_repo_root" diff --name-only origin/main...HEAD 2>/dev/null | grep -E '(^|/)migrations/' )
  if [ -n "$_mig_files" ]; then
    _mig_count=$(printf '%s\n' "$_mig_files" | grep -c .)
    _mig_names=$(printf '%s\n' "$_mig_files" | sed 's|.*/||' | tr '\n' ' ')
    allow_with_context "WARNING: this release PR contains ${_mig_count} migration(s) not in main: ${_mig_names}- deploy-strategy.md: additive schema changes apply the migration BEFORE the deploy. If the shipped code READS a new column, either order works; if it WRITES one, the migration MUST be applied to production BEFORE the deploy, or every write to that table fails in production. State the required order explicitly in the PR body."
  fi
fi

# --- Guard 13: full test suite / build outside the release gate (warning) ---
# Active ONLY when STG_ENABLED=true (two-stage test gate — see CLAUDE.md
# テスト実行の最適化). Trigger: a vitest run with no positional filter (= whole
# suite), pnpm/npm/yarn test with no forwarded filter, or a production build —
# while the target checkout is NOT on release/stg, main, or a hotfix branch.
#
# WHY: the two-stage gate says feature->release/stg needs scoped tests + full
# typecheck only; the full suite and build belong to the release/stg->main gate.
# A rule alone does not change behaviour — full-suite runs keep happening for
# STG-bound fixes, and parallel worktrees each running the whole suite degrade
# the machine. The missing piece is a reminder at the moment of action.
#
# Advisory only (never blocks): a full run on a feature branch is legitimate
# for high-risk changes — that judgement belongs to the author. Detection is
# heuristic and fail-open: matching runs on CLEAN_CMD (quoted text stripped, so
# commit messages mentioning these commands stay silent); an executor-wrapped
# full run is Guard 10's territory. A flag value in space form (--pool x) reads
# as a positional and stays silent — acceptable for an advisory layer.
if [ "$STG_ENABLED_VAL" = "true" ]; then
  _g13_hit=""
  if printf '%s\n' "$CLEAN_CMD" | grep -qE 'vitest[[:space:]]+run'; then
    _g13_rest=$(printf '%s\n' "$CLEAN_CMD" | sed -E 's/.*vitest[[:space:]]+run//; s/(&&|\|\|).*//; s/[;|&].*//')
    _g13_pos=$(printf '%s\n' "$_g13_rest" | tr '[:space:]' '\n' | grep -vE '^$|^-|^[0-9]*[<>]' | head -1)
    [ -z "$_g13_pos" ] && _g13_hit="full-suite vitest run (no file/pattern filter)"
  fi
  if [ -z "$_g13_hit" ] && printf '%s\n' "$CLEAN_CMD" | grep -qE '(^|[[:space:];&|(])(pnpm|npm|yarn)([[:space:]]+run)?[[:space:]]+test([[:space:]]|$)'; then
    _g13_rest=$(printf '%s\n' "$CLEAN_CMD" | sed -E 's/.*(pnpm|npm|yarn)([[:space:]]+run)?[[:space:]]+test//; s/(&&|\|\|).*//; s/[;|&].*//')
    _g13_pos=$(printf '%s\n' "$_g13_rest" | tr '[:space:]' '\n' | grep -vE '^$|^-|^[0-9]*[<>]' | head -1)
    [ -z "$_g13_pos" ] && _g13_hit="full-suite test script"
  fi
  if [ -z "$_g13_hit" ] && printf '%s\n' "$CLEAN_CMD" | grep -qE '(^|[[:space:];&|(])((pnpm|npm|yarn)([[:space:]]+run)?[[:space:]]+build|next[[:space:]]+build)\b'; then
    _g13_hit="production build"
  fi
  if [ -n "$_g13_hit" ]; then
    # Judge by the branch of the directory the command targets: the first
    # `cd <dir>` wins, so `cd ../wt && npx vitest run` is judged by the
    # worktree's branch, not the hook cwd's.
    _g13_dir=$(printf '%s\n' "$CLEAN_CMD" | grep -oE '(^|[;&|[:space:]])cd[[:space:]]+[^;&|[:space:]]+' | head -1 | sed -E 's/^.*cd[[:space:]]+//')
    case "$_g13_dir" in
      ""|/*|[A-Za-z]:*) : ;;                      # absolute (POSIX or Windows) as-is
      *) [ -n "$CWD" ] && _g13_dir="$CWD/$_g13_dir" ;;  # relative: resolve against tool cwd
    esac
    [ -z "$_g13_dir" ] && _g13_dir="${CWD:-.}"
    _g13_branch=$(git -C "$_g13_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
    case "$_g13_branch" in
      release/stg|main|hotfix/*) : ;;  # release gate — the full suite/build is the policy there
      *)
        allow_with_context "WARNING: ${_g13_hit} on branch '${_g13_branch:-unknown}'. CLAUDE.md テスト実行の最適化: the feature->release/stg gate is scoped tests + full typecheck only — the full suite and build belong to the release/stg->main gate. Scope the run (test file / directory / --changed) unless this change is explicitly release-bound or high-risk. Parallel worktrees each running the full suite degrade the whole machine."
        ;;
    esac
  fi
fi

# --- Guard 10: shell executor present (warning) [C-2b] ---
# Reached only when no destructive pattern was found inside the executor AND the
# command was not a forbidden STG PR route (Guard 11 above already denied those).
if [ "$EXECUTOR_PRESENT" -eq 1 ]; then
  allow_with_context "WARNING: shell executor (bash -c / sh -c / eval / xargs / cmd /c) detected. Quote-based guards are weakened inside executors; verify the wrapped command performs no destructive action."
fi

# --- Guard 4.5 deferred emit: template -> .env setup copy (WARNING — see Guard 4.5) ---
# Runs last so every HARD block above takes precedence over this advisory.
if [ "$ENV_WRITE_WARN" -eq 1 ]; then
  allow_with_context "WARNING: creating .env from a template (cp .env.example .env) detected — allowed as first-time setup. Confirm the resulting .env points at the STAGING DB, not production. For production DB operations, pass credentials inline instead: DATABASE_URL=\"prod-string\" node scripts/xxx.js"
fi

allow_silent