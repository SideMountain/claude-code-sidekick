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
# Detects `git commit` across chained commands (git add -A && git commit ...),
# env/wrapper prefixes (FOO=bar / command / env / nice / git), subshells, and
# shell executors (bash -c "..."); quoted "git commit" mentions never fire.
#
# Output: JSON (hookSpecificOutput) to stdout, human-readable to stderr
#
# chmod +x .claude/hooks/guard-commit-message.sh
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
else
  COMMAND=$(printf '%s\n' "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# Fallback: if jq failed (COMMAND is empty but INPUT exists), use grep
if [ -z "$COMMAND" ] && [ -n "$INPUT" ]; then
  COMMAND=$(printf '%s\n' "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# Detect a field-checkable `git commit` anywhere in the command. The old anchor
# only saw a line-leading `git commit` (optionally `cd ... && git commit`), so
# the common `git add -A && git commit -m "..."` chained form skipped the check.
# Strip quotes/HEREDOCs (so a quoted "git commit" mention never fires) and
# normalise `git -C <dir> commit`, then split into segments the same way
# guard-bash.sh does (Guard 2) and inspect each one.
CLEAN_CMD=$(printf '%s\n' "$COMMAND" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g; s/<<'EOF'.*//; s/<<EOF.*//")
CLEAN_CMD=$(normalize_git_cmd "$CLEAN_CMD")

# Match `git commit` ANYWHERE in a segment (\b word boundary), not just at the
# segment start. A leading anchor let any single token before git slip the check
# — env prefix (`FOO=bar git commit`), a wrapper (`command`/`env`/`nice`/`time`/
# `\git`), or a subshell (`(git commit)` / `$(git commit)`). guard-bash's push
# guard is anchor-free for the same reason; mirror it. The leading `\b` still
# keeps `digit`/`legit commit` from false-firing.
_COMMIT_RE='\bgit[[:space:]]+commit\b'

HAS_COMMIT=0
while IFS= read -r _seg; do
  printf '%s\n' "$_seg" | grep -qE "$_COMMIT_RE" || continue
  # --amend segments modify an existing message: skip that segment's field check.
  printf '%s\n' "$_seg" | grep -q '\-\-amend' && continue
  HAS_COMMIT=1
done <<SEGMENTS_EOF
$(printf '%s\n' "$CLEAN_CMD" | sed -E 's/(&&|\|\|)/\n/g; s/[;&|]/\n/g')
SEGMENTS_EOF

# Shell executors (bash -c / sh -c / eval / xargs) carry their payload inside
# the quotes CLEAN_CMD strips, so the segment scan above cannot see a wrapped
# `git commit`. Mirror guard-bash's C-2 double-haystack: when an executor is
# present, also scan the RAW command. The field check runs on the raw $COMMAND
# regardless, so a wrapped commit lacking 背景/対応/影響 is still denied. An
# `--amend` anywhere in the raw executor payload conservatively skips (allow) to
# avoid false-denying an amend-only wrapped commit — same quote-weakened limit
# guard-bash documents for executors.
if [ "$HAS_COMMIT" -eq 0 ] \
   && printf '%s\n' "$COMMAND" | grep -qE '\b(bash|sh)[[:space:]]+-c\b|\beval\b|\bxargs\b' \
   && printf '%s\n' "$COMMAND" | grep -qE "$_COMMIT_RE" \
   && ! printf '%s\n' "$COMMAND" | grep -q '\-\-amend'; then
  HAS_COMMIT=1
fi

# Nothing field-checkable (non-commit command, --amend only, or a quoted
# "git commit" mention) → allow silently.
if [ "$HAS_COMMIT" -eq 0 ]; then
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