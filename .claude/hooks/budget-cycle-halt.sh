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

# Advisory Stop hook — fail-open (ADR-0032). Needs _json_escape (hook-helpers.sh)
# and the budget readers (hook-helpers-budget.sh); both are sourced fail-open so
# a broken/missing helper skips silently rather than trapping the stop (blocking
# a stop over a broken helper would trap the user — only enforcement guards are
# fail-closed).
_ccs_dir="$(dirname "$0")"
. "$_ccs_dir/hook-helpers.sh" 2>/dev/null
. "$_ccs_dir/hook-helpers-budget.sh" 2>/dev/null
if ! command -v _json_escape >/dev/null 2>&1 || ! command -v ccs_budget_read >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)

# --- Configuration ---
CACHE_DIR="${CCS_CACHE_DIR:-$HOME/.claude/.cache}"
RATE_FILE="$CACHE_DIR/ccs-rate-limits.json"
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

# --- Read canonical file (capturer schema) + binding window. "strict" keeps
# this hook's original fallback (grep only when jq is ABSENT), so a malformed
# JSON that jq rejects yields empty pct -> NORMAL -> silent = fail-open
# (ADR-0032). No file -> NORMAL, silent. ---
ccs_budget_read "$RATE_FILE" strict || exit 0
ccs_budget_binding

# Clear a stale wrap-up marker once this session is out of the PAUSE band
_clear_halt_marker() {
  if [ -f "$HALT_MARKER" ] && [ "$(cat "$HALT_MARKER" 2>/dev/null)" = "$SESSION_ID" ]; then
    rm -f "$HALT_MARKER" 2>/dev/null
  fi
}

if [ "$CCS_SEVERITY" = "NORMAL" ]; then
  _clear_halt_marker
  exit 0
fi

# --- Staleness gate: old data must not enforce (fail-open + detection note) ---
if ccs_budget_is_stale "$STALE_SECS"; then
  _clear_halt_marker
  MSG=$(_json_escape "[ccs budget] rate-limit data is stale (captured_at too old) — treating as NORMAL (fail-open). Check that the capturer (statusline ccs-rate-capture.sh) is wired.")
  printf '{"systemMessage":"%s"}\n' "$MSG"
  exit 0
fi

# --- THROTTLE: advisory only, never blocks (decision 3) ---
if [ "$CCS_SEVERITY" = "THROTTLE" ]; then
  _clear_halt_marker
  MSG=$(_json_escape "[ccs budget] THROTTLE: ${CCS_BINDING} cap at ${CCS_BINDING_PCT}% (>= ${CCS_BUDGET_THROTTLE_PCT}%). Narrow the width, not the correctness: suppress fan-out, avoid non-essential upper-model calls, keep outputs concise. Resets at: ${CCS_BINDING_RESET:-unknown}.")
  printf '{"systemMessage":"%s"}\n' "$MSG"
  exit 0
fi

# --- PAUSE: one bounded wrap-up turn, then stop (decision 3) ---
if [ "$STOP_HOOK_ACTIVE" = "true" ] || { [ -f "$HALT_MARKER" ] && [ "$(cat "$HALT_MARKER" 2>/dev/null)" = "$SESSION_ID" ]; }; then
  # Wrap-up turn already ran for this session -> allow the stop.
  MSG=$(_json_escape "[ccs budget] PAUSE: ${CCS_BINDING} cap at ${CCS_BINDING_PCT}% (> ${CCS_BUDGET_PAUSE_PCT}%). Autonomous loop paused until reset (${CCS_BINDING_RESET:-unknown}). State should be persisted in the ledger/commit.")
  printf '{"systemMessage":"%s"}\n' "$MSG"
  exit 0
fi

# Record the wrap-up marker BEFORE blocking (atomic tmp->mv), so the next
# Stop is always allowed through even if stop_hook_active is not provided.
mkdir -p "$CACHE_DIR" 2>/dev/null
printf '%s' "$SESSION_ID" > "$HALT_MARKER.tmp" 2>/dev/null && mv -f "$HALT_MARKER.tmp" "$HALT_MARKER" 2>/dev/null
rm -f "$HALT_MARKER.tmp" 2>/dev/null

REASON=$(_json_escape "[ccs budget-gate] ${CCS_BINDING} cap at ${CCS_BINDING_PCT}% (> ${CCS_BUDGET_PAUSE_PCT}% = PAUSE, ADR-0024). Wrap up NOW in one turn: (1) persist the progress ledger (decisions + why, remaining tasks, next step) to disk, (2) commit completed verifiable work, (3) then stop. Do NOT start new work until the cap resets (${CCS_BINDING_RESET:-unknown}). If seven_day is the binding constraint, switch to weekly-priority triage after reset.")
printf '{"decision":"block","reason":"%s"}\n' "$REASON"
exit 0
