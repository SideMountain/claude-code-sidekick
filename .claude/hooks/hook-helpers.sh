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

# =============================================================================
# DB-pattern configuration reader
#
# Resolves the STG/PRD DB identification substrings so guard-db-operation.sh
# reads them from the authoritative config (CLAUDE.md Project Configuration)
# instead of a hard-coded blank. Without this the enforcement layer (physical
# deny of PRD writes, H1/H2/H6) stays silent even when the config sets a
# pattern — the recognition layer (CLAUDE.md) and the enforcement layer drift
# apart, and editing the script directly is clobbered by /adopt overwrites.
#
# Priority (first hit wins):
#   1. SIDEKICK_<KEY> env var (non-empty) — CI / testing
#   2. CLAUDE.md Project Configuration: the `<KEY>:` YAML scalar value
#   3. "" (empty — fail-open, preserves prior behaviour when nothing is set)
#
# Args: $1 = path to CLAUDE.md, $2 = KEY (STG_DB_PATTERN | PRD_DB_PATTERN).
# Output: the pattern string ("" when unset). Uses printf (no echo); 2>/dev/null.
# =============================================================================
get_db_pattern() {
  local claude_md="${1:-}" key="${2:-}" ov=""

  # 1. Env override (highest priority; closed set — no arbitrary env expansion)
  case "$key" in
    STG_DB_PATTERN) ov="${SIDEKICK_STG_DB_PATTERN:-}" ;;
    PRD_DB_PATTERN) ov="${SIDEKICK_PRD_DB_PATTERN:-}" ;;
  esac
  if [ -n "$ov" ]; then
    printf '%s' "$ov"
    return 0
  fi

  # 2. Parse the `<key>:` scalar from CLAUDE.md Project Configuration.
  #    Scan ALL matching lines (not grep -m1): the shipped template carries an
  #    empty placeholder `<KEY>: ""`, so a first-match read would grab the blank
  #    and fail-open even when a real value is set elsewhere. Clean each value
  #    (drop a whitespace-preceded `# comment` per YAML — a bare `a#b` is kept —
  #    then strip surrounding whitespace and one quote layer), discard empties,
  #    and take the last non-empty (more-protective for PRD: non-empty = deny).
  if [ -n "$claude_md" ] && [ -n "$key" ] && [ -f "$claude_md" ]; then
    local parsed
    parsed=$(grep -E "^[[:space:]]*${key}[[:space:]]*:" "$claude_md" 2>/dev/null \
      | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]+#.*//' \
      | sed -E 's/[[:space:]]*$//; s/^[[:space:]]*//; s/^["'"'"']//; s/["'"'"']$//' \
      | grep -v '^$' | tail -1)
    if [ -n "$parsed" ]; then
      printf '%s' "$parsed"
      return 0
    fi
  fi

  # 3. Fallback (empty — fail-open, unchanged behaviour when unset)
  printf '%s' ""
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

# =============================================================================
# Git command normalizer — defuses `git -C <dir>` / `-c` / `--git-dir` bypass
#
# Strips git's *global* options (those that sit between `git` and the
# subcommand) so guards can see the real subcommand. Without this,
# `git -C . push origin main` slips past a `git\s+push` matcher because of the
# `-C .` wedged in between. Value-taking options (`-C`, `-c`, `--git-dir`,
# `--work-tree`, `--namespace`, `--super-prefix`, `--config-env`) consume their
# argument; the flag options below do not. Idempotent: loops until the string
# stabilises so stacked options (`git -c x=y -C . push`) fully collapse.
# Fails safe: on any miss it returns the input unchanged (guards still see
# whatever subcommand is present).
#
# Usage: GIT_CMD=$(normalize_git_cmd "<command string>")
# =============================================================================
normalize_git_cmd() {
  local cmd="$1" prev=""
  while [ "$cmd" != "$prev" ]; do
    prev="$cmd"
    cmd=$(printf '%s' "$cmd" | sed -E \
      -e 's/(^|[^[:alnum:]_])(git)[[:space:]]+(-C|-c|--git-dir|--work-tree|--namespace|--super-prefix|--config-env)([[:space:]]+|=)[^[:space:]]+/\1\2/g' \
      -e 's/(^|[^[:alnum:]_])(git)[[:space:]]+(-p|--paginate|--no-pager|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-optional-locks)([[:space:]]+)/\1\2\4/g')
  done
  printf '%s' "$cmd"
}

# =============================================================================
# Protected-branch push detector — token-based, anchor-independent
#
# Scans the *arguments* of a `git push` (everything after `git push`) and
# returns 0 if any refspec targets a protected branch. Works regardless of
# trailing flags/tokens (`--quiet`, `-v`, `;`, `--force`) that used to slip a
# protected push past a `$`-anchored matcher. Understands refspecs: for
# `src:dst` it checks the dst side; strips a leading `+` (force) and a
# `refs/heads/` prefix. Option flags (`-x`) are skipped. Globbing is disabled
# for the scan so a stray `*` in the args is not expanded against the fs.
#
# Usage: push_targets_protected_branch "<args after 'git push'>" "<set>"
# =============================================================================
push_targets_protected_branch() {
  local args="$1" set="$2" tok dst rc=1 restore=0
  case $- in *f*) : ;; *) set -f; restore=1 ;; esac
  for tok in $args; do
    case "$tok" in -*) continue ;; esac
    tok="${tok%%;*}"; tok="${tok%%&*}"; tok="${tok%%|*}"
    tok="${tok//\"/}"; tok="${tok//\'/}"; tok="${tok//\`/}"
    [ -z "$tok" ] && continue
    case "$tok" in
      *:*) dst="${tok##*:}" ;;
      *)   dst="$tok" ;;
    esac
    dst="${dst#+}"
    dst="${dst#refs/heads/}"
    if _branch_in_set "$dst" "$set"; then rc=0; break; fi
  done
  [ "$restore" -eq 1 ] && set +f
  return "$rc"
}

# =============================================================================
# Official-skill feature gate — boundary layer (ADR-0027 decision 3)
#
# Official Claude Code skills appear at specific CLI versions and may change
# without notice. This block closes all knowledge of that dependency into one
# place: wrapper skills call ccs_official_gate as a preflight and switch to
# their fallback with an explicit WARN when the feature is unavailable.
# Two invariants:
#   - never break: undetectable/unparsable versions fail OPEN (available),
#     and the gate is advisory (always succeeds, never blocks)
#   - never silent: confirmed unavailability is always surfaced as a WARN
# Pure bash string handling (no jq — version strings are not JSON).
# =============================================================================

# Print the running Claude Code CLI version (e.g. "2.1.201"), or "" when the
# CLI is missing (callers treat "" as undetectable → fail-open).
# Verified output format of `claude --version` (2026-07-04, v2.1.201):
#   "2.1.201 (Claude Code)"  → first whitespace-separated token.
# CCS_CLAUDE_VERSION_OVERRIDE, when *set*, wins — even if empty, so tests and
# CI can simulate an undetectable version without uninstalling the CLI.
ccs_claude_version() {
  if [ -n "${CCS_CLAUDE_VERSION_OVERRIDE+set}" ]; then
    printf '%s' "$CCS_CLAUDE_VERSION_OVERRIDE"
    return 0
  fi
  local out
  out=$(claude --version 2>/dev/null) || out=""
  printf '%s' "${out%% *}"
}

# Feature name → minimum Claude Code version that ships it. Single source of
# truth for official-skill version floors (add new features here only).
# Floors are pinned from the official Claude Code release notes:
#   schedule 2.1.81 / code-review-ultra 2.1.86 / goal 2.1.139 /
#   verify 2.1.145 / run 2.1.145 / simplify 2.1.154 / workflows 2.1.154
# Re-validated 2026-07-04 (WS7 first freshness run): code-review-ultra 2.1.86,
# goal 2.1.139, simplify 2.1.154, workflows 2.1.154 CONFIRMED against release
# notes/docs. schedule CORRECTED 2.1.72 → 2.1.81 (2026-07-04): the official
# CHANGELOG (raw main) lists no schedule/routines introduction earlier than
# this, so we pin the documented minimum from the official routines docs
# (2.1.81). verify/run 2.1.145 remain unconfirmed on re-check — still flagged
# for correction. fail-open keeps an unverified floor safe: it only relaxes a
# WARN, never breaks a wrapper.
# Drift is caught by the weekly-inventory freshness watch (ADR-0027 decision 4).
# Unknown feature → empty output (callers treat it as fail-open).
_ccs_official_min_version() {
  case "$1" in
    schedule)            printf '%s' "2.1.81" ;;
    code-review-ultra)   printf '%s' "2.1.86" ;;
    goal)                printf '%s' "2.1.139" ;;
    verify|run)          printf '%s' "2.1.145" ;;
    simplify|workflows)  printf '%s' "2.1.154" ;;
    *)                   : ;;
  esac
}

# Every official feature ccs wraps, space-separated. The freshness watch
# (weekly-inventory Step 5d, ADR-0027 decision 4) iterates this to detect
# floor/availability drift without re-listing the case keys above.
# INVARIANT: keep this list in sync with _ccs_official_min_version — a new
# wrapped feature must be added to BOTH (add it here so the watch surfaces it).
ccs_official_features() {
  printf '%s' "schedule code-review-ultra goal verify run simplify workflows"
}

# Numeric dotted-version compare: is $1 >= $2 ?
# Returns 0 (yes) / 1 (no) / 2 (either side unparsable — caller fails open).
# Missing components count as 0 ("2.1" == "2.1.0"); leading zeros are safe
# (forced base-10). Empty strings, stray characters, and malformed dots
# ("2.", ".2", "2..1") all yield 2.
_ccs_version_ge() {
  local i n c1 c2
  case "$1" in ''|.*|*.|*..*|*[!0-9.]*) return 2 ;; esac
  case "$2" in ''|.*|*.|*..*|*[!0-9.]*) return 2 ;; esac
  local IFS='.'
  local -a a1 a2
  read -r -a a1 <<<"$1"
  read -r -a a2 <<<"$2"
  n="${#a1[@]}"
  [ "${#a2[@]}" -gt "$n" ] && n="${#a2[@]}"
  for ((i = 0; i < n; i++)); do
    c1="${a1[i]-0}"
    c2="${a2[i]-0}"
    [ "$((10#$c1))" -gt "$((10#$c2))" ] && return 0
    [ "$((10#$c1))" -lt "$((10#$c2))" ] && return 1
  done
  return 0
}

# Is the official feature $1 usable on the running CLI? No output either way.
# Returns 0 = usable, 1 = CLI confirmed below the feature's version floor.
# Fail-open cases (return 0): unknown feature, undetectable version,
# unparsable version — a broken version probe must not disable wrappers
# (ADR-0027 decision 3: the boundary degrades to WARN, never to breakage).
# Usage: ccs_official_available <feature>
ccs_official_available() {
  local feature="$1" min current
  min=$(_ccs_official_min_version "$feature")
  [ -z "$min" ] && return 0             # unknown feature: fail-open
  current=$(ccs_claude_version)
  [ -z "$current" ] && return 0         # version undetectable: fail-open
  _ccs_version_ge "$current" "$min"
  case "$?" in
    1) return 1 ;;                      # confirmed below the floor
    *) return 0 ;;                      # 0 = usable / 2 = unparsable: fail-open
  esac
}

# Preflight for wrapper skills: emits a single WARN line on stdout when the
# official feature is confirmed unavailable, so the wrapper surfaces it and
# switches to its fallback (silent breakage is forbidden). Always returns 0 —
# advisory only, never blocks (ADR-0027 decision 3).
# Usage: ccs_official_gate <feature>
ccs_official_gate() {
  local feature="$1"
  if ! ccs_official_available "$feature"; then
    printf '%s\n' "WARN: official '$feature' unavailable (Claude Code $(ccs_claude_version) < required $(_ccs_official_min_version "$feature")) — use the ccs fallback instead."
  fi
  return 0
}

# =============================================================================
# EOF load sentinel — DO NOT add definitions below this line (ADR-0032)
#
# The fail-closed bootstrap in each enforcement guard checks this flag to prove
# the ENTIRE library parsed. A mid-file syntax error leaves earlier functions
# defined but never reaches this line, so the flag stays unset and the guard
# denies (fail-closed) instead of running with a half-loaded library. Anything
# appended AFTER this line is outside that proof — add new helpers ABOVE, and
# keep this assignment the last statement in the file.
# =============================================================================
_CCS_HELPERS_LOADED=1