#!/bin/bash
# =============================================================================
# replay.sh — regression suite for the fail-closed distribution gate
#
# Covers `distribution-gate.sh` (the caller-side stop/proceed decision used by
# /review Step 0 and /adopt-sidekick-update Step 6.6) together with the
# `verify-distribution.sh` it drives.
#
# The property under test is one-sided: **only a verified-clean tree may return
# 0**. Every other state — companions missing, manifest missing, the verifier
# itself missing, a bootstrap that could not complete, a status nobody
# anticipated — must be non-zero, because each of them is a state in which the
# caller has *not* checked anything and must not act as though it had.
#
# Each case runs the real gate against a scratch repo built from this repo's own
# .claude/ + REVIEW.md, tagged so that bootstrap paths have somewhere to restore
# from (and somewhere to fail to restore from).
#
# Usage: replay.sh [--gate <path>]
#
# The final block additionally executes the real SKILL.md bash fragments, because
# a gate whose caller drops the status is a gate that does not exist.
# Exit: 0 = all cases pass, 1 = at least one failure.
# =============================================================================

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd)
GATE="$REPO_ROOT/.claude/scripts/distribution-gate.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --gate) GATE=$(cd "$(dirname "$2")" && pwd)/$(basename "$2"); shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -f "$GATE" ] || { echo "FAIL: gate not found: $GATE" >&2; exit 2; }

WORK=$(mktemp -d) || exit 2
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
REPO="$WORK/repo"

VERIFIER=".claude/scripts/verify-distribution.sh"
MANIFEST=".claude/scripts/distribution-manifest.tsv"
COMPANION=".claude/skills/review/scripts/review-fitness.sh"

_commit() { git -C "$REPO" add -A && git -C "$REPO" commit -q --no-verify -m "$1

背景: distribution-gate の回帰 fixture
対応: $1
影響: scratch repo のみ"; }

# --- Build the scratch repo and the tags the bootstrap paths need ------------
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" symbolic-ref HEAD refs/heads/main
git -C "$REPO" config user.email gate@example.com
git -C "$REPO" config user.name gate
git -C "$REPO" config commit.gpgsign false
git -C "$REPO" config core.hooksPath "$REPO/.git/no-hooks"
cp -r "$REPO_ROOT/.claude" "$REPO/"
cp "$REPO_ROOT/REVIEW.md" "$REPO/"
_commit "full tree"          && git -C "$REPO" tag t-full
rm -f "$REPO/$VERIFIER"
_commit "verifier removed"   && git -C "$REPO" tag t-noverify
: > "$REPO/$VERIFIER"
_commit "verifier emptied"   && git -C "$REPO" tag t-empty
git -C "$REPO" checkout -q t-full -- .claude REVIEW.md
rm -f "$REPO/$COMPANION"
_commit "companion removed"  && git -C "$REPO" tag t-nocompanion
git -C "$REPO" checkout -q t-full -- .claude REVIEW.md
_commit "back to full" || true

FAILED=0
_reset() { git -C "$REPO" checkout -q t-full -- .claude REVIEW.md; }

_case() {  # $1=name  $2=expected exit  $3...=gate args
  local name="$1" want="$2"; shift 2
  local out st
  out=$( cd "$REPO" && bash "$GATE" "$@" 2>&1 ); st=$?
  if [ "$st" = "$want" ]; then
    printf 'PASS     %-34s exit=%s\n' "$name" "$st"
  else
    printf 'FAIL     %-34s exit=%s (want %s)\n' "$name" "$st" "$want" >&2
    printf '%s\n' "$out" | sed 's/^/           | /' >&2
    FAILED=1
  fi
}

# 1. Everything present → the only state allowed to return 0.
_reset
_case "complete-tree" 0

# 2. A companion a SKILL.md references by path is gone.
_reset; rm -f "$REPO/$COMPANION"
_case "companion-missing" 3

# 3. The manifest itself did not travel: dependencies it alone records cannot be
#    judged, which is not the same as having none.
_reset; rm -f "$REPO/$MANIFEST"
_case "manifest-missing" 4

# 4. The verifier is gone and no ref was offered to restore it. This is the case
#    that must never be mistaken for "nothing to report".
_reset; rm -f "$REPO/$VERIFIER"
_case "verifier-missing-no-ref" 5

# 5. Same, but with a ref that has it → bootstrap, then a clean verify.
_reset; rm -f "$REPO/$VERIFIER"
_case "verifier-missing-bootstrapped" 0 --repair-from t-full

# 6. Companion gone, ref has it → repaired in place, then clean.
_reset; rm -f "$REPO/$COMPANION"
_case "companion-repaired" 0 --repair-from t-full

# 7. Companion gone locally AND at the ref → repair cannot close it, so the
#    gate must still stop rather than report a successful repair run.
_reset; rm -f "$REPO/$COMPANION"
_case "companion-missing-at-ref-too" 3 --repair-from t-nocompanion

# 8. The verifier returns something no case anticipated. An unrecognised status
#    is not a pass; this is the branch that stops a future verifier change from
#    silently opening the gate.
_reset; printf '#!/bin/bash\nexit 42\n' > "$REPO/$VERIFIER"
_case "verifier-unexpected-exit" 7

# 9. Bootstrap source does not contain the object.
_reset; rm -f "$REPO/$VERIFIER"
_case "bootstrap-object-absent" 6 --repair-from t-noverify

# 10. Bootstrap source contains it, but empty. An empty verifier would "run
#     successfully" and check nothing, so it must never reach the filesystem.
_reset; rm -f "$REPO/$VERIFIER"
_case "bootstrap-empty-object" 6 --repair-from t-empty
if [ -s "$REPO/$VERIFIER" ]; then
  echo "FAIL     bootstrap-empty-not-installed     a non-empty verifier appeared where the source was empty" >&2
  FAILED=1
elif [ -f "$REPO/$VERIFIER" ]; then
  echo "FAIL     bootstrap-empty-not-installed     an empty verifier was left in place" >&2
  FAILED=1
else
  echo "PASS     bootstrap-empty-not-installed      (nothing installed)"
fi
# and no temp litter left behind
if ls "$REPO/.claude/scripts/"*.ccs-bootstrap.* >/dev/null 2>&1; then
  echo "FAIL     bootstrap-no-temp-litter           temp file left behind" >&2
  FAILED=1
else
  echo "PASS     bootstrap-no-temp-litter"
fi

# --- Caller propagation ------------------------------------------------------
# The gate returning non-zero is worth nothing if the snippet that calls it
# swallows the status. `bash "$GATE"; GATE_ST=$?` ends on an assignment, and an
# assignment always succeeds — so the whole fragment exits 0 and the caller is
# told everything is fine. Prose saying "stop here" does not execute.
#
# These cases run the ACTUAL fenced bash blocks from the two SKILL.md files, so
# editing those blocks back into the swallowing shape turns this suite red. A
# copy of the snippet kept here would only prove that the copy is correct.
_extract_block() {  # $1=markdown file  $2=anchor heading
  awk -v anchor="$2" '
    index($0, anchor) { a = 1 }
    a && /^```bash$/  { b = 1; next }
    b && /^```$/      { exit }
    b                 { print }
  ' "$1"
}

REVIEW_SNIP="$WORK/review-step0.sh"
ADOPT_SNIP="$WORK/adopt-step66.sh"
_extract_block "$REPO_ROOT/.claude/skills/review/SKILL.md" '## Step 0:' > "$REVIEW_SNIP"
_extract_block "$REPO_ROOT/.claude/skills/adopt-sidekick-update/SKILL.md" '### Step 6.6:' > "$ADOPT_SNIP"

# An anchor that stopped matching would silently yield an empty snippet, and an
# empty script exits 0 — every propagation case below would "pass" while testing
# nothing. Verify the extraction actually captured a gate call first.
for snip in "$REVIEW_SNIP" "$ADOPT_SNIP"; do
  if [ ! -s "$snip" ] || ! grep -q 'distribution-gate\.sh' "$snip"; then
    echo "FAIL: snippet extraction produced nothing usable ($snip) — anchors drifted" >&2
    exit 2
  fi
done

_caller_case() {  # $1=name  $2=expected exit  $3=snippet  $4=LATEST (optional)
  local name="$1" want="$2" snip="$3" latest="${4:-}"
  local out st
  out=$( cd "$REPO" && LATEST="$latest" bash "$snip" 2>&1 ); st=$?
  if [ "$st" = "$want" ]; then
    printf 'PASS     %-34s exit=%s\n' "$name" "$st"
  else
    printf 'FAIL     %-34s exit=%s (want %s)\n' "$name" "$st" "$want" >&2
    printf '%s\n' "$out" | sed 's/^/           | /' >&2
    FAILED=1
  fi
}

# /review Step 0 — verify-only, so a locally missing companion is terminal.
_reset
_caller_case "caller-review-complete" 0 "$REVIEW_SNIP"

_reset; rm -f "$REPO/$MANIFEST"
_caller_case "caller-review-manifest-missing" 4 "$REVIEW_SNIP"

_reset; printf '#!/bin/bash\nexit 42\n' > "$REPO/$VERIFIER"
_caller_case "caller-review-unexpected-exit" 7 "$REVIEW_SNIP"

_reset; rm -f "$REPO/.claude/scripts/distribution-gate.sh"
_caller_case "caller-review-gate-missing" 3 "$REVIEW_SNIP"

# /adopt Step 6.6 — repairs from the tag, so the asymmetry is deliberate: a
# locally missing manifest is restored (0), while one the tag cannot supply is not.
_reset
_caller_case "caller-adopt-complete" 0 "$ADOPT_SNIP" t-full

_reset; rm -f "$REPO/$MANIFEST"
_caller_case "caller-adopt-manifest-repaired" 0 "$ADOPT_SNIP" t-full

_reset; printf '#!/bin/bash\nexit 42\n' > "$REPO/$VERIFIER"
_caller_case "caller-adopt-unexpected-exit" 7 "$ADOPT_SNIP" t-full

_reset; rm -f "$REPO/$COMPANION"
_caller_case "caller-adopt-companion-unfixable" 3 "$ADOPT_SNIP" t-nocompanion

_reset; rm -f "$REPO/$VERIFIER"
_caller_case "caller-adopt-bootstrap-fails" 6 "$ADOPT_SNIP" t-noverify

_reset
if [ "$FAILED" = "1" ]; then
  echo "=== distribution-gate: FAILURES (the gate is not fail-closed) ===" >&2
  exit 1
fi
echo "=== distribution-gate: all cases pass ==="
exit 0
