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