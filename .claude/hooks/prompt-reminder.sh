#!/bin/bash
# =============================================================================
# UserPromptSubmit Hook: Inject critical rules reminder on every prompt
#
# Prevents Claude from skipping rules in favor of task completion speed.
#
# Additionally emits ONE budget cognition line (ADR-0024 decision 4) when the
# rate-cap usage crosses the THROTTLE threshold. Below the threshold — and on
# missing file / stale data / parse failure — nothing is added (zero residency
# pollution, fail-open). The rate-cap parsing is shared with budget-cycle-halt.sh
# via hook-helpers-budget.sh (ADR-0032 decision 3): this hook reads in "loose"
# mode (grep fallback whenever jq yields empty). printf, never echo (CLAUDE.md §3).
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
# Advisory: source the budget helper fail-open. If it cannot load, just skip the
# budget line — the reminder above already printed and must never be blocked.
_ccs_budget_lib="$(dirname "$0")/hook-helpers-budget.sh"
[ -f "$_ccs_budget_lib" ] && . "$_ccs_budget_lib" 2>/dev/null
command -v ccs_budget_read >/dev/null 2>&1 || exit 0

CACHE_DIR="${CCS_CACHE_DIR:-$HOME/.claude/.cache}"
RATE_FILE="$CACHE_DIR/ccs-rate-limits.json"
# captured_at older than this (seconds) -> data too stale to steer cognition
STALE_SECS="${CCS_BUDGET_STALE_SECS:-1800}"

# No data -> nothing added (fail-open, silent). "loose" preserves this hook's
# original grep-on-empty fallback (ADR-0032).
ccs_budget_read "$RATE_FILE" loose || exit 0
ccs_budget_binding

# Below threshold -> nothing added (the common case: zero pollution)
[ "$CCS_SEVERITY" = "NORMAL" ] && exit 0

# Staleness gate: old data must not steer cognition (fail-open, silent here —
# the stale-capturer detection note is budget-cycle-halt's job, not this hook's)
ccs_budget_is_stale "$STALE_SECS" && exit 0

if [ "$CCS_SEVERITY" = "THROTTLE" ]; then
  printf '[ccs budget] cognition: %s cap at %s%% (THROTTLE band, ADR-0024). Suppress fan-out, avoid non-essential subagent/upper-model calls, keep outputs concise.\n' "$CCS_BINDING" "$CCS_BINDING_PCT"
else
  printf '[ccs budget] cognition: %s cap at %s%% (> %s%% — PAUSE imminent, ADR-0024). Prepare the progress ledger (decisions+why / remaining tasks / next step) and commit verifiable work; the Stop gate will halt the loop.\n' "$CCS_BINDING" "$CCS_BINDING_PCT" "$CCS_BUDGET_PAUSE_PCT"
fi
exit 0
