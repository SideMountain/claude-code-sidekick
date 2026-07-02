#!/bin/bash
# =============================================================================
# Shared helper functions for PreToolUse hooks
#
# Provides JSON output functions compliant with the official Claude Code
# hook specification (hookSpecificOutput format).
#
# Usage: source "$(dirname "$0")/hook-helpers.sh"
#
# Functions:
#   deny "reason"           - Block the tool call (permissionDecision: deny)
#   allow_with_context "msg" - Allow with additional context for Claude
#   allow_silent             - Allow without output
#
# All functions output JSON to stdout and human-readable messages to stderr.
# deny and allow_with_context call exit internally — do NOT call exit after them.
# =============================================================================

# Escape string for JSON value (handles \, ", newlines, tabs)
_json_escape() {
  local str="$1"
  str="${str//\\/\\\\}"
  str="${str//\"/\\\"}"
  str="${str//$'\n'/\\n}"
  str="${str//$'\t'/\\t}"
  printf '%s' "$str"
}

# Block the tool call with a reason
# Usage: deny "reason message"
deny() {
  local reason="$1"
  local escaped
  escaped=$(_json_escape "$reason")
  printf '%s\n' "BLOCKED: $reason" >&2
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$escaped"
  exit 0
}

# Allow the tool call but inject context for Claude
# Usage: allow_with_context "context message"
allow_with_context() {
  local context="$1"
  local escaped
  escaped=$(_json_escape "$context")
  printf '%s\n' "$context" >&2
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"%s"}}\n' "$escaped"
  exit 0
}

# Allow silently (no JSON output, just exit 0)
allow_silent() {
  exit 0
}

# =============================================================================
# Protected-branch configuration reader
#
# Resolves the project's protected-branch set so the guards and session-start
# stay in sync with the authoritative config instead of a hard-coded "main".
# This keeps the recognition layer (CLAUDE.md) and the enforcement layer (hooks)
# aligned for STG projects that protect more than one branch.
#
# Priority (first hit wins):
#   1. SIDEKICK_PROTECTED_BRANCHES env var (space-separated) — CI / testing
#   2. CLAUDE.md Project Configuration: the PROTECTED_BRANCHES: YAML list
#   3. "main" (default — preserves prior behaviour when nothing is configured)
#
# Args: $1 = path to CLAUDE.md (optional). Output: space-separated branch names.
# Uses printf + awk (no echo). Fails safe to "main" on any parse miss.
# =============================================================================
get_protected_branches() {
  local claude_md="${1:-}"
  local default_branches="main"

  # 1. Env override (highest priority; useful for CI / testing)
  if [ -n "${SIDEKICK_PROTECTED_BRANCHES:-}" ]; then
    printf '%s' "$SIDEKICK_PROTECTED_BRANCHES"
    return 0
  fi

  # 2. Parse the PROTECTED_BRANCHES: YAML list block from CLAUDE.md
  if [ -n "$claude_md" ] && [ -f "$claude_md" ]; then
    local parsed
    parsed=$(awk '
      done { next }
      /^[[:space:]]*PROTECTED_BRANCHES[[:space:]]*:/ { inblock=1; next }
      inblock == 1 {
        # active list item "  - name" (commented "  # - name" is skipped below)
        if ($0 ~ /^[[:space:]]*-[[:space:]]*[^#[:space:]]/) {
          line = $0
          sub(/#.*/, "", line)                        # strip trailing comment
          sub(/^[[:space:]]*-[[:space:]]*/, "", line)  # strip leading "  - "
          gsub(/[[:space:]"]/, "", line)               # strip spaces and quotes
          if (line != "") printf "%s ", line
          next
        }
        # comment or blank line inside the block: keep scanning
        if ($0 ~ /^[[:space:]]*(#|$)/) { next }
        # any other content line ends the block
        inblock = 0; done = 1
      }
    ' "$claude_md" 2>/dev/null | sed 's/[[:space:]]*$//')
    if [ -n "$parsed" ]; then
      printf '%s' "$parsed"
      return 0
    fi
  fi

  # 3. Fallback (backward compatible: main-only protection)
  printf '%s' "$default_branches"
}

# Exact membership test against a space-separated set (slash-safe, unlike grep -w).
# Usage: _branch_in_set "<branch>" "<space-separated set>"
_branch_in_set() {
  local needle="$1" set="$2" item
  for item in $set; do
    [ "$needle" = "$item" ] && return 0
  done
  return 1
}