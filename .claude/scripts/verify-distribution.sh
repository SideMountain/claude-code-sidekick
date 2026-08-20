#!/bin/bash
# =============================================================================
# verify-distribution.sh — companion-completeness gate for sidekick distribution
#
# Why this exists
# ---------------
# `/adopt-sidekick-update` distributes whatever changed in `v<CURRENT>..<LATEST>`.
# That is a *diff*, not a closure: a skill's companion asset that last changed
# outside the adopted range — or that predates the day its directory was added
# to the distribution filter at all — never travels with the SKILL.md that needs
# it. The downstream PJ ends up with a skill whose first step invokes a file it
# does not have.
#
# Observed shape: a downstream PJ held `.claude/skills/review/SKILL.md` while
# `scripts/review-fitness.sh` and `REVIEW.md` were both absent. `/review` then
# ran and produced a verdict — the deterministic pre-gate and the PJ-norm
# dimension had simply vanished from min(). A missing check that still returns
# "PR作成可" is worse than a check that errors.
#
# So: absence of an asset must be an observation, not a silence.
#
# What it checks
# --------------
# A. Derived — every full repo-relative path under `.claude/{skills,scripts,
#    hooks,githooks,docs}/` ending in .sh/.js/.md that a local SKILL.md, rule or
#    REVIEW.md references must exist. Owners only claim paths they actually
#    invoke or Read, so this rule needs no hand-maintained list and has no
#    false positives to tune (a reference to a file that is not there is a
#    broken reference whatever the reason).
# B. Manifest — `.claude/scripts/distribution-manifest.tsv`, for the hard deps
#    written as bare root-level names (REVIEW.md) that rule A cannot see.
#
# Exit codes (a missing check and an unrunnable check are different answers)
#   0  complete
#   3  EVIDENCE_REQUIRED — at least one required asset is absent
#   4  cannot determine — no owners found, or the manifest is missing
#
# Usage:
#   verify-distribution.sh                     # verify, report to stdout
#   verify-distribution.sh --quiet             # exit code only
#   verify-distribution.sh --repair-from <ref> # fetch the missing files from a
#                                              # git ref (e.g. the release tag
#                                              # /adopt-sidekick-update applies)
#                                              # then re-verify
# =============================================================================

set -u

QUIET=0
REPAIR_REF=""

while [ $# -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1; shift ;;
    --repair-from) REPAIR_REF="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$ROOT" ] || { echo "[ERROR] not inside a git repository — cannot verify distribution" >&2; exit 4; }
cd "$ROOT" || exit 4

MANIFEST=".claude/scripts/distribution-manifest.tsv"

_say() { [ "$QUIET" = "1" ] || printf '%s\n' "$*"; }

# --- Collect owners ----------------------------------------------------------
# Owners are the files that declare dependencies: skill definitions, domain
# rules, and the review norms. Missing owners is itself indeterminate, not clean.
OWNERS=$(find .claude/skills -name SKILL.md -type f 2>/dev/null; \
         find .claude/rules -name '*.md' -type f 2>/dev/null; \
         [ -f REVIEW.md ] && echo REVIEW.md)
OWNERS=$(printf '%s\n' "$OWNERS" | grep -v '^$')

if [ -z "$OWNERS" ]; then
  echo "[ERROR] no SKILL.md / rules / REVIEW.md found under $ROOT — sidekick does not look installed here (not a clean result)" >&2
  exit 4
fi

if [ ! -f "$MANIFEST" ]; then
  echo "[ERROR] $MANIFEST is missing — the companion manifest itself did not travel, so completeness cannot be judged" >&2
  exit 4
fi

# --- Rule A: derived path references ----------------------------------------
# One grep over every owner, then a pure-builtin existence loop. Deduplicated so
# a path referenced by five skills is reported once, with all of its claimants.
REFS=$(printf '%s\n' "$OWNERS" | tr '\n' '\0' | xargs -0 grep -ohE \
  '\.claude/(skills|scripts|hooks|githooks|docs)/[A-Za-z0-9._/-]+\.(sh|js|md)' 2>/dev/null | sort -u)

MISSING=""
for ref in $REFS; do
  [ -e "$ref" ] && continue
  claimants=$(printf '%s\n' "$OWNERS" | tr '\n' '\0' | xargs -0 grep -lF "$ref" 2>/dev/null | tr '\n' ' ')
  MISSING="${MISSING}${ref}"$'\t'"referenced by: ${claimants}"$'\n'
done

# --- Rule B: manifest --------------------------------------------------------
while IFS=$'\t' read -r owner required why; do
  case "$owner" in ''|'#'*) continue ;; esac
  [ -n "${required:-}" ] || continue
  [ -e "$owner" ] || continue          # the owner is not installed → not required
  [ -e "$required" ] && continue
  MISSING="${MISSING}${required}"$'\t'"required by: ${owner} — ${why:-}"$'\n'
done < "$MANIFEST"

# --- Repair ------------------------------------------------------------------
if [ -n "$MISSING" ] && [ -n "$REPAIR_REF" ]; then
  _say "=== verify-distribution: repairing from ${REPAIR_REF} ==="
  repaired=""
  while IFS=$'\t' read -r path _; do
    [ -n "$path" ] || continue
    if git cat-file -e "${REPAIR_REF}:${path}" 2>/dev/null; then
      mkdir -p "$(dirname "$path")"
      if git show "${REPAIR_REF}:${path}" > "$path" 2>/dev/null; then
        # git show writes content only; restore the executable bit in the file
        # and in the index so the next checkout does not lose it again.
        case "$path" in *.sh) chmod +x "$path"; git update-index --add --chmod=+x "$path" 2>/dev/null ;; esac
        repaired="${repaired}${path}"$'\n'
        _say "  restored: $path"
      else
        _say "  FAILED to write: $path"
      fi
    else
      _say "  not present at ${REPAIR_REF}: $path (upstream may have removed it — update the referencing owner instead)"
    fi
  done <<EOF
$(printf '%s' "$MISSING")
EOF
  # Re-verify only what we claimed to fix: a repair that did not land must not
  # be reported as success.
  still=""
  while IFS=$'\t' read -r path rest; do
    [ -n "$path" ] || continue
    [ -e "$path" ] || still="${still}${path}"$'\t'"${rest}"$'\n'
  done <<EOF
$(printf '%s' "$MISSING")
EOF
  MISSING="$still"
fi

# --- Report ------------------------------------------------------------------
if [ -n "$MISSING" ]; then
  if [ "$QUIET" != "1" ]; then
    printf '%s' "$MISSING" | while IFS=$'\t' read -r path why; do
      printf '[EVIDENCE_REQUIRED] %s — 欠落（%s）\n' "$path" "$why"
    done
    n=$(printf '%s' "$MISSING" | grep -c .)
    printf '=== verify-distribution: %s 件の配布欠落。参照元スキルは沈黙のまま dimension を落とすため、配置するまで結果を「合格」と読まないこと ===\n' "$n" >&2
  fi
  exit 3
fi

_say "=== verify-distribution: 配布は完結している（参照先すべて実在）==="
exit 0
