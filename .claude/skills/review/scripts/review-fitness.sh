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
# diff between BASE and HEAD. Stack-agnostic (bash + git + awk, no deps).
#
# Output: one finding per line, "[SEVERITY] file:line — message", to stdout.
# Findings are WARN-class *inputs* to the review's min(); the reviewer confirms
# the final severity per REVIEW.md §2. The hook-enforced BLOCKERs (commit msg,
# PII, protected branch, .env, PRD DB) live in the guards, not here.
#
# Exit code:
#   0 = scanned, no findings
#   1 = scanned, findings present (advisory signal for CI)
#   2 = NOT SCANNED — indeterminate. Never read as "no findings".
#
# Usage: review-fitness.sh [BASE_REF]
#   With no argument, BASE is resolved from the repo's default branch
#   (origin/HEAD → origin/main → main). If none resolves, falls back to the
#   working-tree diff (staged + unstaged), which is what a local pre-commit run
#   wants.
#   With an explicit BASE_REF that does not resolve, the script **fails (2)**
#   rather than falling back. A caller that named a base asked for that base;
#   quietly scanning something else and reporting "no findings" would answer a
#   question nobody asked.
#
# --- Cost structure (why this is one awk and not a grep per line) ------------
# The process count is O(1) in the size of the diff: one `git diff` for *all*
# check classes plus one `awk` that parses the hunks and applies every pattern
# in the same pass. The earlier shape — one `git diff` per check class, then a
# `printf | grep` pipeline per added line per pattern — spawned thousands of
# processes on a large diff. That is roughly free on Linux and pathological on
# Windows (Git Bash / MSYS), where process creation dominates: a 2,000-line
# diff cost ~10 minutes instead of ~0.3 s, which is enough friction that the
# gate stops being run (`Gotchas: fitness を重くしない`).
#
# The observable contract — findings, order, severity, file:line, the stderr
# summary and the exit code — is frozen by tests/fixtures/review-fitness/
# (`replay.sh`). Change it only deliberately.
# =============================================================================

set -u

# --- Resolve the diff range ---------------------------------------------------
# An explicitly supplied base and an auto-resolved one are NOT interchangeable:
# auto-resolution is allowed to come up empty and fall back to the working tree,
# an explicit base is a caller's assertion that this ref is the thing to compare
# against.
BASE="${1:-}"
BASE_EXPLICIT=0
[ -n "$BASE" ] && BASE_EXPLICIT=1

if [ "$BASE_EXPLICIT" = "0" ]; then
  BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@')
  [ -z "$BASE" ] && { git rev-parse --verify -q origin/main >/dev/null 2>&1 && BASE="origin/main"; }
  [ -z "$BASE" ] && { git rev-parse --verify -q main >/dev/null 2>&1 && BASE="main"; }
fi

RANGE=""
if [ -n "$BASE" ]; then
  if git rev-parse --verify -q "$BASE" >/dev/null 2>&1; then
    RANGE="$BASE...HEAD"
  elif [ "$BASE_EXPLICIT" = "1" ]; then
    printf '=== review-fitness: 判定不能 — 明示された BASE_REF "%s" が解決できません ===\n' "$BASE" >&2
    printf '    作業ツリー検査へはフォールバックしません（指定と違う対象を検査して「検出なし」と報告しないため）。\n' >&2
    printf '    ref 名を確認するか、自動解決させる場合は引数なしで実行してください。\n' >&2
    exit 2
  fi
fi

# One diff for every check class. The pathspec is the union of the per-class
# scopes below; awk re-derives the class from the file extension, so widening
# the union never widens a check.
#
#   check 1 (destructive DDL) : *.sql *.prisma
#   check 2 (a11y)            : *.tsx *.jsx *.html *.vue *.svelte
#   check 3 (empty catch)     : *.ts *.tsx *.js *.jsx
PATHSPEC=('*.sql' '*.prisma' '*.tsx' '*.jsx' '*.html' '*.vue' '*.svelte' '*.ts' '*.js')

if [ -n "$RANGE" ]; then
  DIFF_ARGS=("$RANGE")
else
  DIFF_ARGS=(HEAD)
fi

SCRATCH=$(mktemp -d) || {
  printf '=== review-fitness: 判定不能 — 一時ディレクトリを作成できませんでした ===\n' >&2
  exit 2
}
cleanup() { rm -f "$SCRATCH"/* 2>/dev/null; rmdir "$SCRATCH" 2>/dev/null; }
trap cleanup EXIT

OUT="$SCRATCH/findings"
DIFF_ERR="$SCRATCH/diff.err"
AWK_ERR="$SCRATCH/awk.err"

# The awk program below both parses the diff and applies every pattern.
#
# Hunk parsing (unchanged from the per-class version): on "+++ b/<file>" set the
# file and its check classes, on "@@ ... +c,d @@" set the new-file line counter,
# and print/advance on each added ('+') line. Removed ('-') lines do not advance
# the new-file counter, so they are ignored.
#
# Findings are collected into three ordered buckets and flushed per class at
# END, so the output stays grouped by check (DDL, then a11y, then empty catch)
# exactly as the per-class loops produced it.
#
# Word boundaries are written as "(^|[^a-z0-9_])x([^a-z0-9_]|$)" rather than \b:
# \b is a GNU extension that mawk and BusyBox awk do not implement, and this
# script has to run under whatever awk a downstream PJ has. The emulation is
# equivalent for a boolean line match — \b holds exactly where the neighbouring
# character is a non-word character or the string edge.
#
# stderr of both stages is captured rather than discarded, and BOTH stages'
# statuses are inspected via PIPESTATUS. `x=$(a | b)` would report only b's
# status, so a failing `git diff` (unborn repo, bad revision, corrupt object)
# would surface as an empty stream and a perfectly clean verdict.
git diff -U0 "${DIFF_ARGS[@]}" -- "${PATHSPEC[@]}" 2>"$DIFF_ERR" | awk '
BEGIN {
  MSG_DDL   = "破壊的 DDL の可能性（Expand-Contract 2 段階リリース + backfill --dry-run を確認 / deploy-strategy.md）"
  MSG_IMG   = "<img> に alt 属性がない（a11y）"
  MSG_INPUT = "<input> にラベル（aria-label / 関連 label の id）がない可能性（a11y）"
  MSG_CATCH = "空の catch（エラーを握りつぶす。reporter〔captureException/logger〕を呼ぶ / brain 外部依存）"
  nd = 0; na = 0; nc = 0
}

/^\+\+\+ b\// {
  f = $2; sub(/^b\//, "", f)
  is_ddl   = (f ~ /\.(sql|prisma)$/)
  is_a11y  = (f ~ /\.(tsx|jsx|html|vue|svelte)$/)
  is_catch = (f ~ /\.(ts|tsx|js|jsx)$/)
  next
}

/^@@ / { match($0, /\+[0-9]+/); ln = substr($0, RSTART+1, RLENGTH-1) + 0; next }

/^\+/ {
  body = substr($0, 2)
  lo = tolower(body)

  # --- Check 1: breaking migration keywords (Expand-Contract, deploy-strategy) ---
  # DROP COLUMN/TABLE, ALTER ... TYPE, RENAME — destructive DDL that needs a
  # 2-phase release. Advisory: the reviewer confirms the sequencing.
  # Scope: actual DDL-bearing files (*.sql / *.prisma) only. A broad "*migrat*"
  # path glob would also scan docs *about* migrations (e.g. docs/migrations/*.md),
  # where prose like "rename" false-matches the RENAME token; and scanning *.ts
  # would false-match "rename" in ordinary code. Keep the keyword match where DDL
  # is unambiguous. Non-SQL migrations are still covered semantically by REVIEW.md §1c.
  #
  # NOT NULL is intentionally excluded: it false-fires on non-destructive
  # `CREATE TABLE (... NOT NULL)` and additive columns. Adding NOT NULL to an
  # existing table is destructive, but a keyword match cannot tell the two apart
  # — that case is reviewed semantically via REVIEW.md §1c.
  if (is_ddl) {
    if (lo ~ /(^|[^a-z0-9_])(drop[[:space:]]+(column|table)|alter[[:space:]]+.*[[:space:]]type|rename)([^a-z0-9_]|$)/) {
      D[++nd] = sprintf("[WARN] %s:%d — %s", f, ln, MSG_DDL)
    }
  }

  # --- Check 2: a11y (review-design "alt 欠落 / label なし input") ---
  # Require the tag to open AND close (">") on the same added line. A bare
  # multi-line "<img" (prettier-formatted, alt on a later line) has no ">" here,
  # so it is skipped instead of false-flagged; multi-line tags are reviewed via
  # REVIEW.md §1e. Same for <input>.
  if (is_a11y) {
    if (lo ~ /<img([^a-z0-9_>][^>]*)?>/ && lo !~ /(^|[^a-z0-9_])alt=/) {
      A[++na] = sprintf("[WARN] %s:%d — %s", f, ln, MSG_IMG)
    }
    if (lo ~ /<input([^a-z0-9_>][^>]*)?>/ \
        && lo !~ /(^|[^a-z0-9_])(aria-label|aria-labelledby|id)=/ \
        && lo !~ /type=("|.)(hidden|submit|button)/) {
      A[++na] = sprintf("[WARN] %s:%d — %s", f, ln, MSG_INPUT)
    }
  }

  # --- Check 3: empty catch (error swallowing — brain「外部依存」) ---
  # High-precision, single-line only: empty `catch(){}` / `.catch(()=>{})`. The
  # broader cases — multi-line empty catches and catches that swallow without a
  # reporter — are semantic and reviewed via REVIEW.md §1h. Case-sensitive, and
  # no Python: `except: pass` is a different construct this pattern cannot match,
  # so *.py is not scanned here (avoids false confidence).
  if (is_catch) {
    if (body ~ /catch[[:space:]]*([(][^)]*[)])?[[:space:]]*[{][[:space:]]*[}]/ \
        || body ~ /[.]catch[(][[:space:]]*([(][^)]*[)]|function[[:space:]]*[(][^)]*[)])[[:space:]]*(=>)?[[:space:]]*[{][[:space:]]*[}][[:space:]]*[)]/) {
      C[++nc] = sprintf("[WARN] %s:%d — %s", f, ln, MSG_CATCH)
    }
  }

  ln++
  next
}

END {
  for (i = 1; i <= nd; i++) print D[i]
  for (i = 1; i <= na; i++) print A[i]
  for (i = 1; i <= nc; i++) print C[i]
}
' > "$OUT" 2>"$AWK_ERR"
PIPE_STATUS=("${PIPESTATUS[@]}")
GIT_STATUS=${PIPE_STATUS[0]}
AWK_STATUS=${PIPE_STATUS[1]}

# --- Fail loud when the scan did not happen ----------------------------------
# "Could not look" and "looked and found nothing" are different observations.
# Collapsing them into exit 0 is the failure mode this whole gate exists to
# prevent, so it must not be the gate's own behaviour.
if [ "$GIT_STATUS" != "0" ] || [ "$AWK_STATUS" != "0" ]; then
  printf '=== review-fitness: 判定不能 — 走査できませんでした（git diff exit %s / awk exit %s）===\n' \
    "$GIT_STATUS" "$AWK_STATUS" >&2
  printf '    これは「決定的検出なし」ではありません。原因を解消するまで検査済みとして扱わないでください。\n' >&2
  if [ -s "$DIFF_ERR" ]; then
    printf '%s\n' '--- git diff stderr ---' >&2
    cat "$DIFF_ERR" >&2
  fi
  if [ -s "$AWK_ERR" ]; then
    printf '%s\n' '--- awk stderr ---' >&2
    cat "$AWK_ERR" >&2
  fi
  exit 2
fi

# --- Report ------------------------------------------------------------------
# Read and count with builtins rather than `cat` + `grep -c`. This is NOT a
# measured speedup: an interleaved A/B on Windows put the within-variant spread
# well above the between-variant difference, i.e. no effect detected. It is kept
# because `grep -c` returns exit 1 on a zero count, so any future use of its
# status here would read "nothing found" as "the count failed" or vice versa —
# one less exit code to get wrong on a path whose whole job is to not confuse
# "found nothing" with "did not look".
mapfile -t FIND_LINES < "$OUT"
if [ "${#FIND_LINES[@]}" -gt 0 ]; then
  printf '%s\n' "${FIND_LINES[@]}"
  printf '=== review-fitness: %s 件の決定的検出（WARN 入力・レビューが最終 severity を確定）===\n' \
    "${#FIND_LINES[@]}" >&2
  exit 1
fi
printf '=== review-fitness: 決定的検出なし ===\n' >&2
exit 0
