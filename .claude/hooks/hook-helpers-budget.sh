#!/bin/bash
# =============================================================================
# Shared rate-cap (budget) readers — ADVISORY layer (ADR-0024 / ADR-0032)
#
# Sourced by the two budget hooks:
#   prompt-reminder.sh  (UserPromptSubmit) — mode "loose"
#   budget-cycle-halt.sh (Stop)            — mode "strict"
#
# Kept OUT of hook-helpers.sh on purpose (ADR-0032 decision 3): this is the
# higher-churn code (ADR-0024 thresholds / capturer schema) and must not sit in
# the file whose integrity fail-closes every enforcement guard. Both callers
# source this fail-open — a load failure only drops the budget line, it never
# blocks a prompt or a stop.
#
# Reads the canonical rate-limit file written by the capturer
# (.claude/statusline/ccs-rate-capture.sh). printf, never echo (CLAUDE.md §3).
#
# Thresholds (ADR-0024, single source): THROTTLE at pct >= 60, PAUSE at pct > 85.
# Boundary operators are load-bearing: 60.0 -> THROTTLE, 85.0 -> THROTTLE,
# 85.0000001 -> PAUSE. Do not change without updating ADR-0024 + the oracle.
# =============================================================================

CCS_BUDGET_THROTTLE_PCT=60
CCS_BUDGET_PAUSE_PCT=85

# _ccs_is_num <s> : 0 when s is a plain (optionally decimal) number
_ccs_is_num() { printf '%s' "$1" | grep -qE '^[0-9]+(\.[0-9]+)?$'; }

# _ccs_to_epoch <v> : normalize epoch-seconds or ISO8601 to epoch ("" if unknown)
_ccs_to_epoch() {
  local v="$1"
  if printf '%s' "$v" | grep -qE '^[0-9]+$'; then
    printf '%s' "$v"
  elif [ -n "$v" ] && [ "$v" != "null" ]; then
    date -d "$v" +%s 2>/dev/null || date -jf "%Y-%m-%dT%H:%M:%S" "${v%%.*}" +%s 2>/dev/null || printf ''
  fi
}

# ccs_budget_read <rate_file> [mode] : populate CCS_* fields from the file.
#   CCS_CAPTURED_AT / CCS_FIVE_PCT / CCS_FIVE_RESET / CCS_SEVEN_PCT / CCS_SEVEN_RESET
# Returns 1 (and leaves fields empty) when the file is absent.
#
# mode preserves each caller's PRE-consolidation grep-fallback behaviour EXACTLY
# (so a malformed JSON that jq rejects but grep matches keeps diverging between
# the two hooks — see ADR-0032 / the guard oracle malformed-JSON cases):
#   strict (Stop hook)   — grep only when jq is ABSENT; a broken JSON that jq
#                          rejects yields empty pct -> NORMAL -> silent (fail-open)
#   loose  (prompt hook) — grep whenever jq yields empty pct (jq absent OR the
#                          JSON is malformed), matching the prompt hook's guard
ccs_budget_read() {
  local rate_file="$1" mode="${2:-strict}"
  CCS_CAPTURED_AT=""; CCS_FIVE_PCT=""; CCS_FIVE_RESET=""; CCS_SEVEN_PCT=""; CCS_SEVEN_RESET=""
  [ -f "$rate_file" ] || return 1

  if command -v jq &>/dev/null; then
    CCS_CAPTURED_AT=$(jq -r '.captured_at // ""' "$rate_file" 2>/dev/null)
    CCS_FIVE_PCT=$(jq -r '.five_hour.pct // ""' "$rate_file" 2>/dev/null)
    CCS_FIVE_RESET=$(jq -r '.five_hour.resets_at // ""' "$rate_file" 2>/dev/null)
    CCS_SEVEN_PCT=$(jq -r '.seven_day.pct // ""' "$rate_file" 2>/dev/null)
    CCS_SEVEN_RESET=$(jq -r '.seven_day.resets_at // ""' "$rate_file" 2>/dev/null)
  fi

  local do_grep=0
  if ! command -v jq &>/dev/null; then
    do_grep=1                                   # strict + loose: jq absent
  elif [ "$mode" = "loose" ] && [ -z "$CCS_FIVE_PCT" ] && [ -z "$CCS_SEVEN_PCT" ]; then
    do_grep=1                                   # loose only: jq present but empty
  fi
  if [ "$do_grep" -eq 1 ]; then
    CCS_FIVE_PCT=$(grep -o '"five_hour":{"pct":[0-9.]*' "$rate_file" 2>/dev/null | grep -o '[0-9.]*$')
    CCS_SEVEN_PCT=$(grep -o '"seven_day":{"pct":[0-9.]*' "$rate_file" 2>/dev/null | grep -o '[0-9.]*$')
    CCS_CAPTURED_AT=$(grep -o '"captured_at":[0-9]*' "$rate_file" 2>/dev/null | grep -o '[0-9]*$')
  fi
  return 0
}

_ccs_rank() { case "$1" in PAUSE) printf '2';; THROTTLE) printf '1';; *) printf '0';; esac; }

# _ccs_severity <pct> <reset> : NORMAL / THROTTLE / PAUSE for one window.
# now > reset counts as recovered -> NORMAL. Needs CCS_NOW (set by binding).
_ccs_severity() {
  local pct="$1" reset="$2" reset_epoch=""
  _ccs_is_num "$pct" || { printf 'NORMAL'; return; }
  reset_epoch=$(_ccs_to_epoch "$reset")
  if [ -n "$reset_epoch" ] && [ -n "$CCS_NOW" ] && [ "$CCS_NOW" -gt "$reset_epoch" ] 2>/dev/null; then
    printf 'NORMAL'
    return
  fi
  if awk -v p="$pct" -v t="$CCS_BUDGET_PAUSE_PCT" 'BEGIN{exit !(p>t)}'; then
    printf 'PAUSE'
  elif awk -v p="$pct" -v t="$CCS_BUDGET_THROTTLE_PCT" 'BEGIN{exit !(p>=t)}'; then
    printf 'THROTTLE'
  else
    printf 'NORMAL'
  fi
}

# ccs_budget_binding : from the CCS_* fields, set the binding-window result:
#   CCS_SEVERITY / CCS_BINDING / CCS_BINDING_PCT / CCS_BINDING_RESET  (+ CCS_NOW)
# five_hour is primary; seven_day can only RAISE severity (binding constraint).
ccs_budget_binding() {
  CCS_NOW=$(date +%s 2>/dev/null)
  local five_sev seven_sev
  five_sev=$(_ccs_severity "$CCS_FIVE_PCT" "$CCS_FIVE_RESET")
  seven_sev=$(_ccs_severity "$CCS_SEVEN_PCT" "$CCS_SEVEN_RESET")

  CCS_SEVERITY="$five_sev"
  CCS_BINDING="five_hour"
  CCS_BINDING_PCT="$CCS_FIVE_PCT"
  CCS_BINDING_RESET="$CCS_FIVE_RESET"

  if [ "$(_ccs_rank "$seven_sev")" -gt "$(_ccs_rank "$five_sev")" ]; then
    CCS_SEVERITY="$seven_sev"
    CCS_BINDING="seven_day"
    CCS_BINDING_PCT="$CCS_SEVEN_PCT"
    CCS_BINDING_RESET="$CCS_SEVEN_RESET"
  fi
}

# ccs_budget_is_stale <stale_secs> : 0 = stale/unknown (fail-open), 1 = fresh.
# CCS_CAPTURED_AT must be epoch and CCS_NOW must be set (ccs_budget_binding).
ccs_budget_is_stale() {
  local stale_secs="$1" age
  printf '%s' "$CCS_CAPTURED_AT" | grep -qE '^[0-9]+$' || return 0
  [ -n "$CCS_NOW" ] || return 0
  age=$(( CCS_NOW - CCS_CAPTURED_AT ))
  { [ "$age" -ge 0 ] && [ "$age" -le "$stale_secs" ]; } && return 1
  return 0
}
