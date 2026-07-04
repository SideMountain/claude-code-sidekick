#!/bin/bash
# =============================================================================
# UserPromptSubmit Hook: Inject critical rules reminder on every prompt
#
# Prevents Claude from skipping rules in favor of task completion speed.
#
# Additionally emits ONE budget cognition line (ADR-0024 decision 4) when the
# rate-cap usage crosses the THROTTLE threshold. Below the threshold — and on
# missing file / stale data / parse failure — nothing is added (zero residency
# pollution, fail-open). Reads the canonical rate-limit file written by the
# capturer (.claude/statusline/ccs-rate-capture.sh), mirroring the parsing of
# budget-cycle-halt.sh (jq + 2>/dev/null + grep fallback; printf, never echo —
# CLAUDE.md §3). The duplicated parse logic is a deliberate trade-off:
# hook-helpers.sh is being edited concurrently, so consolidation there is
# deferred (flagged as a follow-up candidate).
#
# chmod +x .claude/hooks/prompt-reminder.sh
# =============================================================================

cat <<'REMINDER'
--- CRITICAL RULES REMINDER (hook-injected, do not skip) ---
* DB operations: run `grep "^DATABASE_URL" .env` before every DB operation (no exceptions)
* New work: always create a Worktree (do not switch branches in main workspace)
* Commits: include Background/Changes/Affected-files in commit body (required)
* git push / PR creation: always get user confirmation first
* Production DB operations: present plan, impact, rollback -> get explicit approval
---
REMINDER

# --- Budget cognition line (ADR-0024 decision 4: threshold-gated, else silent) ---

CACHE_DIR="${CCS_CACHE_DIR:-$HOME/.claude/.cache}"
RATE_FILE="$CACHE_DIR/ccs-rate-limits.json"
THROTTLE_PCT=60
PAUSE_PCT=85
# captured_at older than this (seconds) -> data too stale to steer cognition
STALE_SECS="${CCS_BUDGET_STALE_SECS:-1800}"

# No data -> nothing added (fail-open, silent)
[ -f "$RATE_FILE" ] || exit 0

CAPTURED_AT=""
FIVE_PCT=""
FIVE_RESET=""
SEVEN_PCT=""
SEVEN_RESET=""
if command -v jq &>/dev/null; then
  CAPTURED_AT=$(jq -r '.captured_at // ""' "$RATE_FILE" 2>/dev/null)
  FIVE_PCT=$(jq -r '.five_hour.pct // ""' "$RATE_FILE" 2>/dev/null)
  FIVE_RESET=$(jq -r '.five_hour.resets_at // ""' "$RATE_FILE" 2>/dev/null)
  SEVEN_PCT=$(jq -r '.seven_day.pct // ""' "$RATE_FILE" 2>/dev/null)
  SEVEN_RESET=$(jq -r '.seven_day.resets_at // ""' "$RATE_FILE" 2>/dev/null)
fi
if [ -z "$FIVE_PCT" ] && [ -z "$SEVEN_PCT" ]; then
  # grep fallback for the capturer's compact JSON (jq missing or failed)
  FIVE_PCT=$(grep -o '"five_hour":{"pct":[0-9.]*' "$RATE_FILE" 2>/dev/null | grep -o '[0-9.]*$')
  SEVEN_PCT=$(grep -o '"seven_day":{"pct":[0-9.]*' "$RATE_FILE" 2>/dev/null | grep -o '[0-9.]*$')
  CAPTURED_AT=$(grep -o '"captured_at":[0-9]*' "$RATE_FILE" 2>/dev/null | grep -o '[0-9]*$')
fi

NOW=$(date +%s 2>/dev/null)

_is_num() {
  printf '%s' "$1" | grep -qE '^[0-9]+(\.[0-9]+)?$'
}

# resets_at may be epoch seconds or ISO8601 — normalize to epoch ("" if unknown)
_to_epoch() {
  local v="$1"
  if printf '%s' "$v" | grep -qE '^[0-9]+$'; then
    printf '%s' "$v"
  elif [ -n "$v" ] && [ "$v" != "null" ]; then
    date -d "$v" +%s 2>/dev/null || date -jf "%Y-%m-%dT%H:%M:%S" "${v%%.*}" +%s 2>/dev/null || printf ''
  fi
}

# Severity of one window: NORMAL / THROTTLE / PAUSE (now > resets_at -> recovered)
_severity() {
  local pct="$1" reset="$2" reset_epoch=""
  _is_num "$pct" || { printf 'NORMAL'; return; }
  reset_epoch=$(_to_epoch "$reset")
  if [ -n "$reset_epoch" ] && [ -n "$NOW" ] && [ "$NOW" -gt "$reset_epoch" ] 2>/dev/null; then
    printf 'NORMAL'
    return
  fi
  if awk -v p="$pct" -v t="$PAUSE_PCT" 'BEGIN{exit !(p>t)}'; then
    printf 'PAUSE'
  elif awk -v p="$pct" -v t="$THROTTLE_PCT" 'BEGIN{exit !(p>=t)}'; then
    printf 'THROTTLE'
  else
    printf 'NORMAL'
  fi
}

FIVE_SEV=$(_severity "$FIVE_PCT" "$FIVE_RESET")
SEVEN_SEV=$(_severity "$SEVEN_PCT" "$SEVEN_RESET")

# five_hour primary; seven_day may only raise severity (binding constraint)
SEVERITY="$FIVE_SEV"
BINDING="five_hour"
BINDING_PCT="$FIVE_PCT"
_rank() { case "$1" in PAUSE) printf '2';; THROTTLE) printf '1';; *) printf '0';; esac; }
if [ "$(_rank "$SEVEN_SEV")" -gt "$(_rank "$FIVE_SEV")" ]; then
  SEVERITY="$SEVEN_SEV"
  BINDING="seven_day"
  BINDING_PCT="$SEVEN_PCT"
fi

# Below threshold -> nothing added (the common case: zero pollution)
[ "$SEVERITY" = "NORMAL" ] && exit 0

# Staleness gate: old data must not steer cognition (fail-open, silent here —
# the stale-capturer detection note is budget-cycle-halt's job, not this hook's)
printf '%s' "$CAPTURED_AT" | grep -qE '^[0-9]+$' || exit 0
[ -n "$NOW" ] || exit 0
AGE=$(( NOW - CAPTURED_AT ))
{ [ "$AGE" -ge 0 ] && [ "$AGE" -le "$STALE_SECS" ]; } || exit 0

if [ "$SEVERITY" = "THROTTLE" ]; then
  printf '[ccs budget] cognition: %s cap at %s%% (THROTTLE band, ADR-0024). Suppress fan-out, avoid non-essential subagent/upper-model calls, keep outputs concise.\n' "$BINDING" "$BINDING_PCT"
else
  printf '[ccs budget] cognition: %s cap at %s%% (> %s%% — PAUSE imminent, ADR-0024). Prepare the progress ledger (decisions+why / remaining tasks / next step) and commit verifiable work; the Stop gate will halt the loop.\n' "$BINDING" "$BINDING_PCT" "$PAUSE_PCT"
fi
exit 0
