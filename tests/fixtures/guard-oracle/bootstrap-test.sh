#!/bin/bash
# =============================================================================
# Fail-closed bootstrap test (Issue #103 / ADR-0032)
#
# The oracle (cases.jsonl / replay.sh) exercises the guards against a HEALTHY
# helper library. This complements it by corrupting the library and asserting
# each enforcement guard DENIES rather than silently allowing (fail-open).
#
# Two blocks:
#   SEALED  — load-failure vectors the bootstrap closes. Must all pass.
#   CEILING — loaded-but-tampered vectors the bootstrap does NOT close (a
#             separate trust boundary, ADR-0032). These are XFAIL: recorded as
#             bypasses so the suite stays green while documenting the hole. When
#             a future change seals them (env-scrub for hook shells), flip the
#             expectation to DENY.
#
# Usage: bash tests/fixtures/guard-oracle/bootstrap-test.sh <repo-root>
# =============================================================================
set -u
REPO="${1:?usage: bootstrap-test.sh <repo-root>}"
GUARDS=(guard-bash.sh guard-db-operation.sh guard-commit-message.sh guard-protected-branch-edit.sh)
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

# Per-guard benign stdin that would normally be ALLOWED (so a deny proves the
# bootstrap fired, not the guard's own logic).
benign_stdin() {
  case "$1" in
    guard-protected-branch-edit.sh) printf '{"tool_input":{"file_path":"/tmp/x.txt"}}' ;;
    *)                              printf '{"tool_input":{"command":"ls -la"}}' ;;
  esac
}

observe() {  # <output> -> deny | allow_silent | allow_ctx
  if [ -z "$1" ]; then printf 'allow_silent'
  elif printf '%s' "$1" | grep -q '"permissionDecision":"deny"'; then printf 'deny'
  elif printf '%s' "$1" | grep -q '"permissionDecision":"allow"'; then printf 'allow_ctx'
  else printf 'unknown'; fi
}

# Stage a guard + a given helper body into an isolated dir, run it, echo observe.
# $1 guard  $2 helper-writer(fn name, writes to $DIR/hook-helpers.sh)  $3 extra-env
run_variant() {
  local guard="$1" writer="$2" extra_env="${3:-}"
  local DIR="$WORK/$RANDOM$RANDOM"; mkdir -p "$DIR"
  cp "$REPO/.claude/hooks/$guard" "$DIR/$guard"
  "$writer" "$DIR"
  local out
  if [ -n "$extra_env" ]; then
    out=$(benign_stdin "$guard" | env $extra_env bash "$DIR/$guard" 2>/dev/null)
  else
    out=$(benign_stdin "$guard" | bash "$DIR/$guard" 2>/dev/null)
  fi
  observe "$out"
}

# --- helper-body writers ---
w_missing()  { : ; }                                             # no hook-helpers.sh
w_syntax()   { { printf 'deny(){ printf X; }\n'; printf 'oops ((((\n'; printf '_CCS_HELPERS_LOADED=1\n'; } > "$1/hook-helpers.sh"; }
w_topexit()  { { printf 'deny(){ printf X; }\n'; printf 'exit 3\n'; printf '_CCS_HELPERS_LOADED=1\n'; } > "$1/hook-helpers.sh"; }
w_stdout()   { { printf 'echo GARBAGE\n'; printf 'deny(){ printf X; }\n'; printf 'broken ((((\n'; } > "$1/hook-helpers.sh"; }
w_healthy()  { cp "$REPO/.claude/hooks/hook-helpers.sh" "$1/hook-helpers.sh"; }

check() {  # <label> <observed> <expected>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); # printf 'ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf 'FAIL %s: observed=%s expected=%s\n' "$1" "$2" "$3"; fi
}

echo "=== SEALED: load-failure vectors must DENY across all enforcement guards ==="
for g in "${GUARDS[@]}"; do
  check "$g missing"      "$(run_variant "$g" w_missing)"  deny
  check "$g syntax-error" "$(run_variant "$g" w_syntax)"   deny
  check "$g top-exit(F1)" "$(run_variant "$g" w_topexit)"  deny
  check "$g stdout(F2)"   "$(run_variant "$g" w_stdout)"   deny
  check "$g env-sentinel" "$(run_variant "$g" w_missing "_CCS_HELPERS_LOADED=1")" deny
  # healthy + benign stdin must NOT be denied by the bootstrap (control)
  obs="$(run_variant "$g" w_healthy)"
  case "$obs" in deny) FAIL=$((FAIL+1)); printf 'FAIL %s healthy-control: bootstrap denied a benign call\n' "$g";; *) PASS=$((PASS+1));; esac
done

echo "=== CEILING (XFAIL, ADR-0032): loaded-but-tampered vectors still bypass ==="
# BASH_ENV injects a readonly no-op deny() before the healthy lib loads; the
# lib's own deny() redefinition fails (readonly), the sentinel still sets, the
# bootstrap passes, and deny() is a no-op. Recorded as a known bypass.
INJ="$WORK/inj.sh"; printf 'deny(){ exit 0; }\nreadonly -f deny 2>/dev/null\n' > "$INJ"
obs="$(run_variant guard-bash.sh w_healthy "BASH_ENV=$INJ")"
if [ "$obs" != "deny" ]; then
  PASS=$((PASS+1)); printf 'XFAIL guard-bash BASH_ENV+readonly deny: bypass=%s (known ceiling — env-scrub is the fix)\n' "$obs"
else
  # Sealed upstream: turn this into a real assertion.
  PASS=$((PASS+1)); printf 'NOTE guard-bash BASH_ENV vector now DENIES — ceiling closed; promote this to a SEALED assertion.\n'
fi

printf '=== bootstrap-test: %d PASS / %d FAIL ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
