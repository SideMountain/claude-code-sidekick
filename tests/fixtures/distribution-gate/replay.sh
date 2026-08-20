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
GATE_REL=".claude/scripts/distribution-gate.sh"
REVIEW_MD="REVIEW.md"

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
rm -f "$REPO/$GATE_REL"
_commit "gate removed"       && git -C "$REPO" tag t-nogate
git -C "$REPO" checkout -q t-full -- .claude REVIEW.md
_commit "back to full" || true

# A stand-in for the ccs remote: Step 0a fetches tags from here, so cases can
# start from the realistic state of "the tag exists upstream, not yet locally".
CCS_REMOTE="$WORK/ccs-remote"
git clone -q --bare "$REPO" "$CCS_REMOTE" 2>/dev/null || { echo "FAIL: could not build ccs remote" >&2; exit 2; }
git -C "$REPO" remote add ccs "$CCS_REMOTE"

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
STEP0B_SNIP="$WORK/adopt-step0b.sh"
STEP0A_SNIP="$WORK/adopt-step0a.sh"
STEP0A0B_SNIP="$WORK/adopt-step0a0b.sh"
_extract_block "$REPO_ROOT/.claude/skills/review/SKILL.md" '## Step 0:' > "$REVIEW_SNIP"
_extract_block "$REPO_ROOT/.claude/skills/adopt-sidekick-update/SKILL.md" '### Step 6.6:' > "$ADOPT_SNIP"
_extract_block "$REPO_ROOT/.claude/skills/adopt-sidekick-update/SKILL.md" '#### Step 0b:' > "$STEP0B_SNIP"
_extract_block "$REPO_ROOT/.claude/skills/adopt-sidekick-update/SKILL.md" '#### Step 0a:' > "$STEP0A_SNIP"
cat "$STEP0A_SNIP" "$STEP0B_SNIP" > "$STEP0A0B_SNIP"

# An anchor that stopped matching would silently yield an empty snippet, and an
# empty script exits 0 — every propagation case below would "pass" while testing
# nothing. Verify the extraction actually captured a gate call first.
for snip in "$REVIEW_SNIP" "$ADOPT_SNIP" "$STEP0B_SNIP"; do
  if [ ! -s "$snip" ] || ! grep -q 'distribution-gate\.sh' "$snip"; then
    echo "FAIL: snippet extraction produced nothing usable ($snip) — anchors drifted" >&2
    exit 2
  fi
done

# Step 0b は「同一バージョンでも補修してから終える」経路そのものが本体なので、
# ゲート呼び出しが在るだけでは足りない。--repair-from と、成功時にだけ出す完了表示の
# 両方を掴んでいることまで確かめる（片方でも欠ければ、以下の same-version 群は
# 別のブロックを実行して緑になりうる）。
for needle in '--repair-from' '取り込み済み'; do
  if ! grep -qF -- "$needle" "$STEP0B_SNIP"; then
    echo "FAIL: Step 0b snippet lacks '$needle' — extracted the wrong block" >&2
    exit 2
  fi
done

# Step 0a must actually fetch AND prove the tag resolves; either half alone lets
# a normal, not-yet-fetched PJ be rejected as "absent at ref".
for needle in 'git fetch ccs --tags' 'rev-parse'; do
  if ! grep -qF -- "$needle" "$STEP0A_SNIP"; then
    echo "FAIL: Step 0a snippet lacks '$needle' — extracted the wrong block" >&2
    exit 2
  fi
done

# Route separation: fetching belongs to 0a only. A fetch that crept back into 0b
# would mean the "no writes before approval" property is being carried by luck.
if grep -qF -- 'git fetch' "$STEP0B_SNIP"; then
  echo "FAIL: Step 0b fetches — the fetch belongs to Step 0a alone" >&2
  exit 2
fi

# The two bootstraps are deliberately duplicated (the routes are exclusive), so
# the thing that must not drift is their text. Compare the delimited sections.
_bootstrap_of() {  # $1=snippet
  awk '/gate-bootstrap:begin/ { b=1 } b { print } /gate-bootstrap:end/ { exit }' "$1"
}
_bootstrap_of "$STEP0B_SNIP" > "$WORK/bs-0b.txt"
_bootstrap_of "$ADOPT_SNIP"  > "$WORK/bs-66.txt"
if [ ! -s "$WORK/bs-0b.txt" ] || [ ! -s "$WORK/bs-66.txt" ]; then
  echo "FAIL: gate-bootstrap sentinels missing — drift check cannot run" >&2
  exit 2
elif ! cmp -s "$WORK/bs-0b.txt" "$WORK/bs-66.txt"; then
  echo "FAIL: Step 0b and Step 6.6 bootstraps have drifted apart" >&2
  diff "$WORK/bs-0b.txt" "$WORK/bs-66.txt" | sed 's/^/           | /' >&2
  exit 2
else
  echo "PASS     bootstrap-texts-identical"
fi

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

# --- Same-version repair path (Step 0b) --------------------------------------
# The blocker this closes: a downstream PJ that adopted this release with its
# OLD /adopt never ran the new Step 6.6 (a running skill does not switch to the
# new instructions mid-flight), so its closure can be incomplete. Re-running the
# NEW /adopt used to early-exit on "already adopted" and never reach a repair —
# and REVIEW.md, unchanged in this range, is never restored by a diff-based
# distribution. So "CURRENT == LATEST" must verify, not conclude.
#
# The property: the completion message may appear ONLY on exit 0. Every
# non-zero path must stay silent about being adopted.
_sv_case() {  # $1=name $2=want-exit $3=CURRENT $4=LATEST $5=expect-done(yes|no)
  local name="$1" want="$2" cur="$3" lat="$4" done_want="$5"
  local out st
  out=$( cd "$REPO" && CURRENT="$cur" LATEST="$lat" bash "$STEP0B_SNIP" 2>&1 ); st=$?
  local ok=1
  [ "$st" = "$want" ] || ok=0
  if printf '%s' "$out" | grep -qF '取り込み済み'; then
    [ "$done_want" = "yes" ] || ok=0
  else
    [ "$done_want" = "no" ] || ok=0
  fi
  if [ "$ok" = "1" ]; then
    printf 'PASS     %-34s exit=%s done-msg=%s\n' "$name" "$st" "$done_want"
  else
    printf 'FAIL     %-34s exit=%s (want %s) done-msg-want=%s\n' "$name" "$st" "$want" "$done_want" >&2
    printf '%s\n' "$out" | sed 's/^/           | /' >&2
    FAILED=1
  fi
}

# 1. Same version, nothing missing → the one state allowed to report completion.
_reset
_sv_case "sv-complete" 0 t-full t-full yes

# 2. REVIEW.md is exactly the file this release does NOT touch, so no diff-based
#    adoption restores it. The same-version path must repair it from the tag.
_reset; rm -f "$REPO/$REVIEW_MD"
_sv_case "sv-review-md-repaired" 0 t-full t-full yes

# 3. The gate itself never travelled → bootstrap it from the tag, then repair.
_reset; rm -f "$REPO/$GATE_REL"
_sv_case "sv-gate-bootstrapped" 0 t-full t-full yes
if [ ! -x "$REPO/$GATE_REL" ]; then
  echo "FAIL     sv-gate-executable                 bootstrapped gate is not executable" >&2
  FAILED=1
else
  echo "PASS     sv-gate-executable"
fi

# 4. Missing locally AND at the tag → repair cannot close it; must not report done.
_reset; rm -f "$REPO/$COMPANION"
_sv_case "sv-companion-unfixable" 3 t-nocompanion t-nocompanion no

# 5. The verifier answers with a status nobody enumerated.
_reset; printf '#!/bin/bash\nexit 42\n' > "$REPO/$VERIFIER"
_sv_case "sv-verifier-unexpected-exit" 7 t-full t-full no

# 6. The gate is absent locally and at the tag → bootstrap fails, stop at 6.
_reset; rm -f "$REPO/$GATE_REL"
_sv_case "sv-gate-absent-at-ref" 6 t-nogate t-nogate no

# 7. Different versions → this block decides nothing, says nothing, and writes
#    nothing. (A block that announced completion here would mark an un-started
#    adoption as finished; one that wrote here would put un-approved files into
#    the adoption diff before the user has chosen any category.)
_reset
_sv_case "sv-update-path-silent" 0 t-nocompanion t-full no

# --- Route separation: which step is allowed to touch the working tree --------
# Step 0b owns the same-version recovery; Step 6.6 owns the end-of-adoption check
# for a normal update. Exactly one of them runs per invocation, and only after
# the user's category choices have been applied may anything appear on disk.
_snapshot() { (cd "$REPO" && git status --porcelain | LC_ALL=C sort); }

_route_case() {  # $1=name $2=want-exit $3=CURRENT $4=LATEST $5=done(yes|no) $6=snippet $7=expect-writes(yes|no)
  local name="$1" want="$2" cur="$3" lat="$4" done_want="$5" snip="$6" writes="$7"
  local before after out st ok=1
  before=$(_snapshot)
  out=$( cd "$REPO" && CURRENT="$cur" LATEST="$lat" bash "$snip" 2>&1 ); st=$?
  after=$(_snapshot)
  [ "$st" = "$want" ] || ok=0
  if printf '%s' "$out" | grep -qF '取り込み済み'; then
    [ "$done_want" = "yes" ] || ok=0
  else
    [ "$done_want" = "no" ] || ok=0
  fi
  if [ "$before" = "$after" ]; then
    [ "$writes" = "no" ] || ok=0
  else
    [ "$writes" = "yes" ] || ok=0
  fi
  if [ "$ok" = "1" ]; then
    printf 'PASS     %-34s exit=%s done=%s writes=%s\n' "$name" "$st" "$done_want" "$writes"
  else
    printf 'FAIL     %-34s exit=%s (want %s) done-want=%s writes-want=%s\n' "$name" "$st" "$want" "$done_want" "$writes" >&2
    printf '%s\n' "$out" | sed 's/^/           | /' >&2
    printf '  status-before: %s\n  status-after:  %s\n' "$before" "$after" >&2
    FAILED=1
  fi
}

# A. The realistic first run: the tag exists upstream but not yet locally.
#    Reaching for `git cat-file "$LATEST:..."` before fetching would reject a
#    perfectly normal PJ as "absent at ref" (exit 6). Step 0a must fetch first.
_reset; git -C "$REPO" tag -d t-full >/dev/null 2>&1
rm -f "$REPO/$REVIEW_MD"
_route_case "route-fetch-then-sv-repair" 0 t-full t-full yes "$STEP0A0B_SNIP" yes
git -C "$REPO" fetch -q ccs --tags 2>/dev/null   # keep later cases usable

# B. Normal update (versions differ) with the gate absent: Step 0a+0b must leave
#    the tree exactly as they found it — no gate, no files, nothing to explain in
#    a diff the user has not approved yet.
_reset; rm -f "$REPO/$GATE_REL"
_route_case "route-update-writes-nothing" 0 t-nocompanion t-full no "$STEP0A0B_SNIP" no
if [ -e "$REPO/$GATE_REL" ]; then
  echo "FAIL     route-update-gate-not-created      the gate was bootstrapped before the user approved anything" >&2
  FAILED=1
else
  echo "PASS     route-update-gate-not-created"
fi

# C. …and the same normal-update run reaches Step 6.6 after applying, where the
#    gate IS bootstrapped (executable), the companion repaired, and the verdict 0.
_caller_case "route-update-then-66-bootstrap" 0 "$ADOPT_SNIP" t-full
if [ -x "$REPO/$GATE_REL" ]; then
  echo "PASS     route-66-gate-executable"
else
  echo "FAIL     route-66-gate-executable           Step 6.6 left the gate missing or non-executable" >&2
  FAILED=1
fi

# D. Fetch itself fails (offline, bad remote, revoked access). "Could not fetch"
#    is not "nothing changed upstream": stop, stay silent about completion, and
#    do not write.
_reset; git -C "$REPO" remote set-url ccs "$WORK/no-such-remote"
_route_case "route-fetch-failure" 4 t-full t-full no "$STEP0A0B_SNIP" no
git -C "$REPO" remote set-url ccs "$CCS_REMOTE"

# 8. No bootstrap temp file survives any of the above.
if ls "$REPO/.claude/scripts/"*.tmp >/dev/null 2>&1; then
  echo "FAIL     sv-no-temp-litter                  temp file left behind" >&2
  FAILED=1
else
  echo "PASS     sv-no-temp-litter"
fi

_reset
if [ "$FAILED" = "1" ]; then
  echo "=== distribution-gate: FAILURES (the gate is not fail-closed) ===" >&2
  exit 1
fi
echo "=== distribution-gate: all cases pass ==="
exit 0
