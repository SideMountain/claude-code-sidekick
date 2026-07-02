#!/bin/bash
# =============================================================================
# Stop Hook: budget-gate — staged control at the Stop boundary (ADR-0024)
#
# Reads the canonical rate-limit file written by the capturer
# (.claude/statusline/ccs-rate-capture.sh -> ~/.claude/.cache/ccs-rate-limits.json)
# and applies ADR-0024 decision 3 at the Stop boundary:
#
#   < 60%   NORMAL   : silent (no injection — zero pollution, decision 4)
#   60-85%  THROTTLE : advisory systemMessage only (never blocks work)
#   > 85%   PAUSE    : one bounded wrap-up turn — block the stop ONCE with
#                      instructions to persist the ledger + commit, then stop.
#
# Re-entry guard (no infinite block loop): a per-session marker file records
# that the wrap-up turn already ran -> the next Stop is allowed through.
# stop_hook_active (when present in the input) is honored as well.
#
# five_hour is the primary window; seven_day can only raise the severity
# (binding constraint). Safety guards are independent of budget state and
# run before this hook (decision 5) — this hook never short-circuits them.
#
# Fail-open (decision 5): missing file / missing jq data / null pct /
# unparseable input / stale captured_at / now past resets_at  -> NORMAL.
# API-key or fresh sessions without rate_limits are never blocked.
#
# Output: official Stop-hook JSON to stdout
#   block: {"decision":"block","reason":"..."}
#   note : {"systemMessage":"..."}
# NOTE: Uses printf instead of echo for JSON piping (echo expands backslashes
#       in Windows paths, breaking jq parsing)
#
# chmod +x .claude/hooks/budget-cycle-halt.sh
# =============================================================================

source "$(dirname "$0")/hook-helpers.sh"

INPUT=$(cat)

# --- Configuration ---
CACHE_DIR="${CCS_CACHE_DIR:-$HOME/.claude/.cache}"
RATE_FILE="$CACHE_DIR/ccs-rate-limits.json"
THROTTLE_PCT=60
PAUSE_PCT=85
# captured_at older than this (seconds) -> data too stale to enforce (fail-open)
STALE_SECS="${CCS_BUDGET_STALE_SECS:-1800}"

# Marker recording that the PAUSE wrap-up turn already ran for a session
HALT_MARKER="$CACHE_DIR/ccs-budget-halt.marker"

# --- Parse hook input ---
STOP_HOOK_ACTIVE=""
SESSION_ID=""
if command -v jq &>/dev/null; then
  STOP_HOOK_ACTIVE=$(printf '%s\n' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
  SESSION_ID=$(printf '%s\n' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
fi
if [ -z "$STOP_HOOK_ACTIVE" ] && [ -n "$INPUT" ]; then
  # grep fallback (jq missing or failed)
  if printf '%s\n' "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
    STOP_HOOK_ACTIVE="true"
  else
    STOP_HOOK_ACTIVE="false"
  fi
fi
if [ -z "$SESSION_ID" ] && [ -n "$INPUT" ]; then
  SESSION_ID=$(printf '%s\n' "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi
[ -z "$SESSION_ID" ] && SESSION_ID="unknown"

# --- No data -> NORMAL (fail-open, silent) ---
[ -f "$RATE_FILE" ] || exit 0

# --- Read canonical file (capturer schema, ADR-0024 decision 2) ---
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
else
  # grep fallback for the capturer's compact JSON ("five_hour":{"pct":42.5,...})
  FIVE_PCT=$(grep -o '"five_hour":{"pct":[0-9.]*' "$RATE_FILE" 2>/dev/null | grep -o '[0-9.]*$')
  SEVEN_PCT=$(grep -o '"seven_day":{"pct":[0-9.]*' "$RATE_FILE" 2>/dev/null | grep -o '[0-9.]*$')
  CAPTURED_AT=$(grep -o '"captured_at":[0-9]*' "$RATE_FILE" 2>/dev/null | grep -o '[0-9]*$')
fi

NOW=$(date +%s 2>/dev/null)

# Numeric check: returns 0 when $1 is a plain (possibly decimal) number
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

# Severity of one window: NORMAL / THROTTLE / PAUSE
# now > resets_at counts as recovered -> NORMAL (decision 5)
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
BINDING_RESET="$FIVE_RESET"
_rank() { case "$1" in PAUSE) printf '2';; THROTTLE) printf '1';; *) printf '0';; esac; }
if [ "$(_rank "$SEVEN_SEV")" -gt "$(_rank "$FIVE_SEV")" ]; then
  SEVERITY="$SEVEN_SEV"
  BINDING="seven_day"
  BINDING_PCT="$SEVEN_PCT"
  BINDING_RESET="$SEVEN_RESET"
fi

# Clear a stale wrap-up marker once this session is out of the PAUSE band
_clear_halt_marker() {
  if [ -f "$HALT_MARKER" ] && [ "$(cat "$HALT_MARKER" 2>/dev/null)" = "$SESSION_ID" ]; then
    rm -f "$HALT_MARKER" 2>/dev/null
  fi
}

if [ "$SEVERITY" = "NORMAL" ]; then
  _clear_halt_marker
  exit 0
fi

# --- Staleness gate: old data must not enforce (fail-open + detection note) ---
IS_STALE=true
if printf '%s' "$CAPTURED_AT" | grep -qE '^[0-9]+$' && [ -n "$NOW" ]; then
  AGE=$(( NOW - CAPTURED_AT ))
  if [ "$AGE" -ge 0 ] && [ "$AGE" -le "$STALE_SECS" ]; then
    IS_STALE=false
  fi
fi
if [ "$IS_STALE" = "true" ]; then
  _clear_halt_marker
  MSG=$(_json_escape "[ccs budget] rate-limit data is stale (captured_at too old) — treating as NORMAL (fail-open). Check that the capturer (statusline ccs-rate-capture.sh) is wired.")
  printf '{"systemMessage":"%s"}\n' "$MSG"
  exit 0
fi

# --- THROTTLE: advisory only, never blocks (decision 3) ---
if [ "$SEVERITY" = "THROTTLE" ]; then
  _clear_halt_marker
  MSG=$(_json_escape "[ccs budget] THROTTLE: ${BINDING} cap at ${BINDING_PCT}% (>= ${THROTTLE_PCT}%). Narrow the width, not the correctness: suppress fan-out, avoid non-essential upper-model calls, keep outputs concise. Resets at: ${BINDING_RESET:-unknown}.")
  printf '{"systemMessage":"%s"}\n' "$MSG"
  exit 0
fi

# --- PAUSE: one bounded wrap-up turn, then stop (decision 3) ---
if [ "$STOP_HOOK_ACTIVE" = "true" ] || { [ -f "$HALT_MARKER" ] && [ "$(cat "$HALT_MARKER" 2>/dev/null)" = "$SESSION_ID" ]; }; then
  # Wrap-up turn already ran for this session -> allow the stop.
  MSG=$(_json_escape "[ccs budget] PAUSE: ${BINDING} cap at ${BINDING_PCT}% (> ${PAUSE_PCT}%). Autonomous loop paused until reset (${BINDING_RESET:-unknown}). State should be persisted in the ledger/commit.")
  printf '{"systemMessage":"%s"}\n' "$MSG"
  exit 0
fi

# Record the wrap-up marker BEFORE blocking (atomic tmp->mv), so the next
# Stop is always allowed through even if stop_hook_active is not provided.
mkdir -p "$CACHE_DIR" 2>/dev/null
printf '%s' "$SESSION_ID" > "$HALT_MARKER.tmp" 2>/dev/null && mv -f "$HALT_MARKER.tmp" "$HALT_MARKER" 2>/dev/null
rm -f "$HALT_MARKER.tmp" 2>/dev/null

REASON=$(_json_escape "[ccs budget-gate] ${BINDING} cap at ${BINDING_PCT}% (> ${PAUSE_PCT}% = PAUSE, ADR-0024). Wrap up NOW in one turn: (1) persist the progress ledger (decisions + why, remaining tasks, next step) to disk, (2) commit completed verifiable work, (3) then stop. Do NOT start new work until the cap resets (${BINDING_RESET:-unknown}). If seven_day is the binding constraint, switch to weekly-priority triage after reset.")
printf '{"decision":"block","reason":"%s"}\n' "$REASON"
exit 0
