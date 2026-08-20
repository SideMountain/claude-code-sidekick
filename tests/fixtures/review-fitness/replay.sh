#!/bin/bash
# =============================================================================
# replay.sh — characterization test for review-fitness.sh
#
# Freezes the *observable contract* of the fitness pre-gate: which findings are
# emitted, in which order, with which severity, file:line and message — plus the
# stderr summary and the exit code — across the invocation modes the script
# supports (auto-resolved BASE...HEAD, explicit BASE, working-tree fallback),
# and the failure modes where it must refuse to answer.
#
# It exists so the implementation can be rewritten (per-line `grep` fan-out →
# single-pass awk) without silently changing what the reviewer sees. The golden
# files under expected/ were generated from the pre-rewrite implementation; a
# rewrite that changes them is a contract change, not a refactor.
#
# Two kinds of scenario:
#   golden    — byte-exact comparison of exit code + stdout + stderr
#   assertion — for indeterminate cases, where the exact text comes from git and
#               varies by version and locale. These assert the contract instead:
#               non-zero exit, no findings, and stderr that says 判定不能 and
#               does NOT say 決定的検出なし.
#
# Usage:
#   replay.sh                       # verify
#   replay.sh --script <path>       # test a specific implementation
#   replay.sh --update              # write only MISSING goldens (existing kept)
#   replay.sh --update-all          # overwrite every golden (destroys provenance)
#
# Exit: 0 = all scenarios pass, 1 = at least one mismatch.
# =============================================================================

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd)
SCRIPT="$REPO_ROOT/.claude/skills/review/scripts/review-fitness.sh"
UPDATE=0
UPDATE_ALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --script) SCRIPT=$(cd "$(dirname "$2")" && pwd)/$(basename "$2"); shift 2 ;;
    --update) UPDATE=1; shift ;;
    --update-all) UPDATE=1; UPDATE_ALL=1; shift ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -f "$SCRIPT" ] || { echo "FAIL: script not found: $SCRIPT" >&2; exit 2; }

CASES="$HERE/cases"
EXPECTED="$HERE/expected"
mkdir -p "$EXPECTED"

WORK=$(mktemp -d) || exit 2
trap 'rm -f "$WORK"/.err "$WORK"/.diff 2>/dev/null; rm -rf "$WORK" 2>/dev/null' EXIT

# Build a scratch repo whose default branch is $2, with one empty base commit.
# Isolated from the outer repo's config (hooksPath, signing, templates).
_new_repo() {
  local dir="$1" branch="$2"
  mkdir -p "$dir" || return 1
  git -C "$dir" init -q || return 1
  git -C "$dir" symbolic-ref HEAD "refs/heads/$branch" || return 1
  git -C "$dir" config user.email fitness@example.com
  git -C "$dir" config user.name fitness
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" config core.hooksPath "$dir/.git/no-hooks"   # never inherit the outer repo's guards
  git -C "$dir" commit -q --allow-empty --no-verify -m base || return 1
}

# Same, but deliberately left unborn (no commit at all).
_new_repo_unborn() {
  local dir="$1"
  mkdir -p "$dir" || return 1
  git -C "$dir" init -q || return 1
  git -C "$dir" symbolic-ref HEAD refs/heads/trunk || return 1
  git -C "$dir" config user.email fitness@example.com
  git -C "$dir" config user.name fitness
  git -C "$dir" config core.hooksPath "$dir/.git/no-hooks"
}

# Run the script under test in $1 and render exit code + stdout + stderr.
_capture() {
  local dir="$1"; shift
  local out err st
  out=$(cd "$dir" && bash "$SCRIPT" "$@" 2>"$WORK/.err"); st=$?
  err=$(cat "$WORK/.err")
  printf '=== exit: %s ===\n--- stdout ---\n%s\n--- stderr ---\n%s\n' "$st" "$out" "$err"
}

FAILED=0
_pass() { echo "PASS     $1"; }
_fail() { echo "FAIL     $1${2:+ — $2}" >&2; FAILED=1; }

_check() {   # golden scenario
  local name="$1" actual="$2"
  local golden="$EXPECTED/$name.txt"
  if [ "$UPDATE" = "1" ]; then
    if [ -f "$golden" ] && [ "$UPDATE_ALL" != "1" ]; then
      echo "KEPT     $name (already has a golden; --update-all to overwrite)"
      return 0
    fi
    printf '%s' "$actual" > "$golden"
    echo "UPDATED  $name"
    return 0
  fi
  if [ ! -f "$golden" ]; then
    _fail "$name" "no golden file ($golden). Run with --update."
    return 1
  fi
  if printf '%s' "$actual" | diff -u "$golden" - > "$WORK/.diff"; then
    _pass "$name"
  else
    _fail "$name"
    cat "$WORK/.diff" >&2
  fi
}

# Assertion scenario: the scan did not happen, and the script says so.
# Deliberately not a golden — the underlying git message is version- and
# locale-dependent, and pinning it would make the test brittle in exactly the
# environments (downstream, Windows, CI) it most needs to work in.
_check_indeterminate() {   # $1=name  $2=dir  $3...=args
  local name="$1" dir="$2"; shift 2
  local out st err
  out=$(cd "$dir" && bash "$SCRIPT" "$@" 2>"$WORK/.err"); st=$?
  err=$(cat "$WORK/.err")
  [ "$UPDATE" = "1" ] && { echo "SKIP     $name (assertion scenario, no golden)"; return 0; }

  if [ "$st" = "0" ] || [ "$st" = "1" ]; then
    _fail "$name" "exit=$st — an unscannable tree must not produce a scanned verdict"; return 1
  fi
  if [ -n "$out" ]; then
    _fail "$name" "stdout was not empty; findings must not be reported from a scan that did not run"; return 1
  fi
  case "$err" in
    *判定不能*) : ;;
    *) _fail "$name" "stderr does not say 判定不能: $err"; return 1 ;;
  esac
  # Match the verdict LINE, not the bare phrase: the indeterminate diagnostic
  # itself contains 「決定的検出なし」ではありません, and a substring test would
  # match the script's own explanation of what it is not.
  case "$err" in
    *"=== review-fitness: 決定的検出なし ==="*)
      _fail "$name" "stderr carries the clean-scan verdict line"; return 1 ;;
  esac
  _pass "$name (exit=$st, indeterminate)"
}

# --- Scenario 1 & 2: BASE...HEAD --------------------------------------------
# Corpus committed on a feature branch; `main` exists locally so the script's
# own BASE resolution finds it (scenario 1), and it is also passed explicitly
# (scenario 2) to pin the documented `review-fitness.sh [BASE_REF]` contract.
R1="$WORK/range"
_new_repo "$R1" main || { echo "FAIL: scratch repo setup" >&2; exit 2; }
git -C "$R1" checkout -q -b feature
cp -r "$CASES/." "$R1/"
git -C "$R1" add -A
git -C "$R1" commit -q --no-verify -m corpus

_check range          "$(_capture "$R1")"
_check range-explicit "$(_capture "$R1" main)"

# --- Scenario 3: working-tree fallback --------------------------------------
# No origin, and the only branch is `trunk`, so neither origin/HEAD, origin/main
# nor main resolves → RANGE is empty → the script diffs the working tree
# (staged + unstaged) against HEAD. This is the local pre-commit path.
R2="$WORK/worktree"
_new_repo "$R2" trunk || { echo "FAIL: scratch repo setup" >&2; exit 2; }
cp -r "$CASES/." "$R2/"
git -C "$R2" add -A          # staged, deliberately not committed

_check worktree "$(_capture "$R2")"

# --- Scenario 4: clean tree --------------------------------------------------
# No added lines anywhere → no findings, "決定的検出なし" on stderr, exit 0.
R3="$WORK/clean"
_new_repo "$R3" main || { echo "FAIL: scratch repo setup" >&2; exit 2; }
git -C "$R3" checkout -q -b feature

_check clean "$(_capture "$R3")"

# --- Scenario 5: explicit BASE that does not resolve -------------------------
# Runs against R2, whose staged corpus WOULD yield findings via the working-tree
# fallback. That is what makes this discriminating: an implementation that
# quietly falls back reports a pile of findings from a tree the caller never
# asked about, and exits 1 as though it had honoured the request. Refusing is
# the only answer that is not a lie.
_check_indeterminate invalid-explicit-base "$R2" no-such-ref-xyz

# --- Scenario 6: git diff fails (unborn repo) --------------------------------
# `git diff HEAD` cannot work before the first commit. The failure has to travel
# out of the pipeline: with `x=$(git diff | awk …)` only awk's status is visible,
# awk happily processes an empty stream, and the gate reports a clean scan of a
# repository it never read.
R4="$WORK/unborn"
_new_repo_unborn "$R4" || { echo "FAIL: scratch repo setup" >&2; exit 2; }
cp -r "$CASES/." "$R4/"
git -C "$R4" add -A

_check_indeterminate unborn-repo "$R4"

if [ "$FAILED" = "1" ]; then
  echo "=== characterization: MISMATCH (contract changed) ===" >&2
  exit 1
fi
echo "=== characterization: all scenarios pass ==="
exit 0
