#!/bin/bash
# =============================================================================
# bench.sh — wall-time harness for review-fitness.sh on a synthetic diff
#
# Builds a scratch repo containing a synthetic feature branch of ~N added lines
# across the scanned extensions, then runs a given implementation R times and
# reports each run's wall time plus a checksum of stdout.
#
# The checksum is the point as much as the timing: an implementation that is
# fast because it stopped detecting things is not faster. Compare the checksum
# across implementations before comparing the milliseconds.
#
# Run it under the shell whose process-creation cost you care about — the whole
# reason this harness exists is that Git Bash on Windows and bash on Linux have
# wildly different fork costs, so a Linux-only measurement says nothing about
# the environment that was actually slow.
#
# Usage:
#   bench.sh [--script PATH] [--runs 3] [--lines 2000] [--keep]
#
# To measure the pre-rewrite implementation, extract it from git first:
#   git show <commit>:.claude/skills/review/scripts/review-fitness.sh > /tmp/old.sh
#   bench.sh --script /tmp/old.sh
# =============================================================================

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd)
SCRIPT="$REPO_ROOT/.claude/skills/review/scripts/review-fitness.sh"
RUNS=3
LINES=2000
KEEP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --script) SCRIPT=$(cd "$(dirname "$2")" && pwd)/$(basename "$2"); shift 2 ;;
    --runs)   RUNS="$2"; shift 2 ;;
    --lines)  LINES="$2"; shift 2 ;;
    --keep)   KEEP=1; shift ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -f "$SCRIPT" ] || { echo "bench: script not found: $SCRIPT" >&2; exit 2; }

WORK=$(mktemp -d) || exit 2
[ "$KEEP" = "1" ] || trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
mkdir -p "$REPO/app" "$REPO/lib" "$REPO/db" "$REPO/web" "$REPO/ui"
git -C "$REPO" init -q
git -C "$REPO" symbolic-ref HEAD refs/heads/main
git -C "$REPO" config user.email fitness@example.com
git -C "$REPO" config user.name fitness
git -C "$REPO" config commit.gpgsign false
git -C "$REPO" config core.hooksPath "$REPO/.git/no-hooks"
git -C "$REPO" commit -q --allow-empty --no-verify -m base
git -C "$REPO" checkout -q -b bench

# --- Synthesise the diff -----------------------------------------------------
# Every generated line is an *added* line, so the whole file counts toward the
# scanned volume. The mix is deliberately realistic rather than adversarial:
# roughly a third of the lines match a check, the rest exercise the negative
# path — which is where a per-line implementation spent most of its budget
# anyway, since a miss still costs a process.
#
# .tsx carries the largest share on purpose: it is the only extension in *both*
# the a11y and the empty-catch scope, so it is the worst case for a per-line
# implementation (most patterns applied per line).
GEN='
function emit(path, text) { print text >> path }
BEGIN {
  n_tsx  = int(total * 0.40)
  n_ts   = int(total * 0.25)
  n_sql  = int(total * 0.15)
  n_html = int(total * 0.10)
  n_jsx  = total - n_tsx - n_ts - n_sql - n_html

  tsx[0] = "      <img src=\"/asset-%d.png\" />"
  tsx[1] = "      <img src=\"/ok-%d.png\" alt=\"ok %d\" />"
  tsx[2] = "      <input type=\"text\" class=\"field-%d\" />"
  tsx[3] = "      <input id=\"f%d\" type=\"email\" />"
  tsx[4] = "      const label%d = t(\"field.%d\")"
  tsx[5] = "      try { save%d() } catch (e) {}"
  tsx[6] = "      try { save%d() } catch (e) { report(e) }"
  tsx[7] = "      const row%d = rows.map((r) => r.id + %d)"
  for (i = 0; i < n_tsx; i++) emit("app/Widget.tsx", sprintf(tsx[i % 8], i, i))

  ts[0] = "export function job%d() { return work(%d) }"
  ts[1] = "  return work().catch(() => {})"
  ts[2] = "  return work().catch((e) => report(e))"
  ts[3] = "  try { flush%d() } catch {}"
  ts[4] = "  const cfg%d = { retries: %d }"
  ts[5] = "  logger.info(\"step %d done\")"
  for (i = 0; i < n_ts; i++) emit("lib/service.ts", sprintf(ts[i % 6], i, i))

  sql[0] = "ALTER TABLE t%d DROP COLUMN legacy_%d;"
  sql[1] = "ALTER TABLE t%d ADD COLUMN note_%d text;"
  sql[2] = "CREATE INDEX t%d_idx ON t%d (label);"
  sql[3] = "ALTER TABLE t%d RENAME COLUMN a TO b_%d;"
  sql[4] = "INSERT INTO t%d (label) VALUES (%d);"
  for (i = 0; i < n_sql; i++) emit("db/001.sql", sprintf(sql[i % 5], i, i))

  html[0] = "  <img src=\"/banner-%d.png\">"
  html[1] = "  <input name=\"q%d\">"
  html[2] = "  <p>section %d</p>"
  html[3] = "  <img src=\"/ok-%d.png\" alt=\"ok\">"
  for (i = 0; i < n_html; i++) emit("web/page.html", sprintf(html[i % 4], i, i))

  jsx[0] = "export const C%d = () => <img src=\"c%d.png\" />"
  jsx[1] = "export const D%d = () => run().catch(() => {})"
  jsx[2] = "export const E%d = () => <span>{%d}</span>"
  for (i = 0; i < n_jsx; i++) emit("ui/legacy.jsx", sprintf(jsx[i % 3], i, i))
}'

# Generated paths are relative, so run the generator with the repo as cwd.
( cd "$REPO" && awk -v total="$LINES" "$GEN" </dev/null ) || { echo "bench: generation failed" >&2; exit 2; }

git -C "$REPO" add -A
git -C "$REPO" commit -q --no-verify -m synthetic

ADDED=$(git -C "$REPO" diff -U0 main...bench | grep -c '^+[^+]')
echo "=== bench: $SCRIPT ==="
echo "added lines: $ADDED   runs: $RUNS   bash: $BASH_VERSION   awk: $(awk --version 2>/dev/null | head -1)"

_now_ms() { date +%s%3N 2>/dev/null || echo $(( $(date +%s) * 1000 )); }

for r in $(seq 1 "$RUNS"); do
  t0=$(_now_ms)
  ( cd "$REPO" && bash "$SCRIPT" main > "$WORK/out.$r" 2> "$WORK/err.$r" )
  st=$?
  t1=$(_now_ms)
  sum=$(cksum < "$WORK/out.$r" | awk '{print $1"/"$2}')
  echo "run $r: $(( t1 - t0 )) ms   exit=$st   findings=$(grep -c '^\[' "$WORK/out.$r")   cksum=$sum"
done

if [ "$KEEP" = "1" ]; then
  echo "kept: $WORK"
  echo "  last stdout: $WORK/out.$RUNS"
fi
exit 0
