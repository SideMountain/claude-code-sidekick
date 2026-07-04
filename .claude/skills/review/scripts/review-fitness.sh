#!/bin/bash
# =============================================================================
# review-fitness.sh — deterministic pre-gate for the /review adapter (WS2)
#
# Runs the mechanical checks that used to live as prose in 4+ review skills
# (breaking-migration keyword detection was duplicated across review-code,
# review-ops, review-spec and rules/deploy-strategy.md). Consolidating them
# here means the LLM review never re-derives what a grep can decide, and the
# detection logic has a single source of truth (diagnosis DRY #1).
#
# Scope: added lines only (so pre-existing issues are not re-flagged) of the
# diff between BASE and HEAD. Stack-agnostic (bash + git + awk + grep, no deps).
#
# Output: one finding per line, "[SEVERITY] file:line — message", to stdout.
# Exit code: 0 = no findings, 1 = findings present (advisory signal for CI).
# Findings are WARN-class *inputs* to the review's min(); the reviewer confirms
# the final severity per REVIEW.md §2. The hook-enforced BLOCKERs (commit msg,
# PII, protected branch, .env, PRD DB) live in the guards, not here.
#
# Usage: review-fitness.sh [BASE_REF]
#   BASE_REF defaults to the repo's default branch (origin/HEAD). When no base
#   is resolvable, falls back to the working-tree diff (staged + unstaged),
#   which is what a local pre-commit run wants.
# =============================================================================

set -u

# --- Resolve the diff range ---------------------------------------------------
BASE="${1:-}"
if [ -z "$BASE" ]; then
  BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@')
  [ -z "$BASE" ] && { git rev-parse --verify -q origin/main >/dev/null 2>&1 && BASE="origin/main"; }
  [ -z "$BASE" ] && { git rev-parse --verify -q main >/dev/null 2>&1 && BASE="main"; }
fi

# Build the git-diff prefix: "<base>...HEAD" when a base resolved and differs
# from HEAD, otherwise the working-tree diff (empty range).
RANGE=""
if [ -n "$BASE" ] && git rev-parse --verify -q "$BASE" >/dev/null 2>&1; then
  RANGE="$BASE...HEAD"
fi

# Emit added lines as "file:line:content" for the given pathspecs.
# Parses `git diff -U0` hunks: on "+++ b/<file>" set the file, on "@@ ... +c,d @@"
# set the new-file line counter, and print/advance on each added ('+') line.
# Removed ('-') lines do not advance the new-file counter, so they are ignored.
_added_lines() {
  if [ -n "$RANGE" ]; then
    git diff -U0 "$RANGE" -- "$@" 2>/dev/null
  else
    git diff -U0 HEAD -- "$@" 2>/dev/null
  fi | awk '
    /^\+\+\+ b\// { f=$2; sub(/^b\//, "", f); next }
    /^@@ / { match($0, /\+[0-9]+/); ln = substr($0, RSTART+1, RLENGTH-1) + 0; next }
    /^\+/  { print f ":" ln ":" substr($0, 2); ln++; next }
  '
}

FINDINGS=""
add_finding() { FINDINGS="${FINDINGS}[$1] $2 — $3"$'\n'; }

# --- Check 1: breaking migration keywords (Expand-Contract, rules/deploy-strategy) ---
# DROP COLUMN/TABLE, ALTER ... TYPE, RENAME, ADD ... NOT NULL — destructive DDL
# that needs a 2-phase release. Advisory: the reviewer confirms the sequencing.
# Scope: actual DDL-bearing files (*.sql / *.prisma) only. A broad "*migrat*"
# path glob would also scan docs *about* migrations (e.g. docs/migrations/*.md),
# where prose like "rename" false-matches the RENAME token; and scanning *.ts
# would false-match "rename" in ordinary code. Keep the keyword grep where DDL
# is unambiguous. Non-SQL migrations are still covered semantically by REVIEW.md §1c.
while IFS= read -r rec; do
  [ -z "$rec" ] && continue
  file="${rec%%:*}"; line="${rec#*:}"; line="${line%%:*}"; body="${rec#*:*:}"
  # NOT NULL is intentionally excluded: it false-fires on non-destructive
  # `CREATE TABLE (... NOT NULL)` and additive columns. Adding NOT NULL to an
  # existing table is destructive, but grep cannot tell the two apart — that
  # case is reviewed semantically via REVIEW.md §1c.
  if printf '%s' "$body" | grep -qiE '\b(DROP[[:space:]]+(COLUMN|TABLE)|ALTER[[:space:]]+.*[[:space:]]TYPE|RENAME)\b'; then
    add_finding WARN "$file:$line" "破壊的 DDL の可能性（Expand-Contract 2 段階リリース + backfill --dry-run を確認 / deploy-strategy.md）"
  fi
done <<EOF
$(_added_lines '*.sql' '*.prisma')
EOF

# --- Check 2: a11y (review-design "alt 欠落 / label なし input") ---
while IFS= read -r rec; do
  [ -z "$rec" ] && continue
  file="${rec%%:*}"; line="${rec#*:}"; line="${line%%:*}"; body="${rec#*:*:}"
  # Require the tag to open AND close ('>') on the same added line. A bare
  # multi-line `<img` (prettier-formatted, alt on a later line) has no '>' here,
  # so it is skipped instead of false-flagged; multi-line tags are reviewed via
  # REVIEW.md §1e. Same for <input> below.
  if printf '%s' "$body" | grep -qiE '<img\b[^>]*>' && ! printf '%s' "$body" | grep -qiE '\balt='; then
    add_finding WARN "$file:$line" "<img> に alt 属性がない（a11y）"
  fi
  if printf '%s' "$body" | grep -qiE '<input\b[^>]*>' \
     && ! printf '%s' "$body" | grep -qiE '\b(aria-label|aria-labelledby|id)=' \
     && ! printf '%s' "$body" | grep -qiE 'type=("|.)(hidden|submit|button)'; then
    add_finding WARN "$file:$line" "<input> にラベル（aria-label / 関連 label の id）がない可能性（a11y）"
  fi
done <<EOF
$(_added_lines '*.tsx' '*.jsx' '*.html' '*.vue' '*.svelte')
EOF

# --- Check 3: empty catch (error swallowing — brain「外部依存」) ---
# High-precision, single-line only: empty `catch(){}` / `.catch(()=>{})`. The
# broader cases — multi-line empty catches and catches that swallow without a
# reporter — are semantic and reviewed via REVIEW.md §1h. No Python: `except:
# pass` is a different construct the JS/TS regex cannot match, so *.py is not
# scanned here (avoids false confidence).
while IFS= read -r rec; do
  [ -z "$rec" ] && continue
  file="${rec%%:*}"; line="${rec#*:}"; line="${line%%:*}"; body="${rec#*:*:}"
  if printf '%s' "$body" | grep -qE 'catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*\}' \
     || printf '%s' "$body" | grep -qE '\.catch\([[:space:]]*(\([^)]*\)|function[[:space:]]*\([^)]*\))[[:space:]]*(=>)?[[:space:]]*\{[[:space:]]*\}[[:space:]]*\)'; then
    add_finding WARN "$file:$line" "空の catch（エラーを握りつぶす。reporter〔captureException/logger〕を呼ぶ / brain 外部依存）"
  fi
done <<EOF
$(_added_lines '*.ts' '*.tsx' '*.js' '*.jsx')
EOF

# --- Report ------------------------------------------------------------------
if [ -n "$FINDINGS" ]; then
  printf '%s' "$FINDINGS"
  n=$(printf '%s' "$FINDINGS" | grep -c '^\[')
  printf '=== review-fitness: %s 件の決定的検出（WARN 入力・レビューが最終 severity を確定）===\n' "$n" >&2
  exit 1
fi
printf '=== review-fitness: 決定的検出なし ===\n' >&2
exit 0
