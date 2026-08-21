#!/bin/bash
# =============================================================================
# replay.sh — 純粋関数の回帰（ADR-0035 決定 10）
#
# 判定（真理値表・policy 合成）は副作用を持たない純粋関数なので、実プロセスを
# 起動せず JSON fixture で網羅する。受入条件は **判定ループ 50 ms 未満**
# （module import と fixture 読み込みを除く）。wall は Node 起動と import が
# 支配的で環境により桁が変わるため、受入条件にしない。
#
# 使い方: replay.sh [--node <path>]
# Exit: 0 = 全件一致 / 1 = 不一致あり / 2 = 実行不能
# =============================================================================

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
NODE_BIN="node"

while [ $# -gt 0 ]; do
  case "$1" in
    --node) NODE_BIN="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v "$NODE_BIN" >/dev/null 2>&1 || { echo "FAIL: node が見つかりません: $NODE_BIN" >&2; exit 2; }

# fixture の存在検査は実行シェル（WSL）のパスで行う。
CASES="$HERE/cases/cases.json"
EXPECTED="$HERE/expected/expected.json"
[ -f "$CASES" ] || { echo "FAIL: cases が無い: $CASES" >&2; exit 2; }
[ -f "$EXPECTED" ] || { echo "FAIL: expected が無い: $EXPECTED" >&2; exit 2; }

# node へ渡すパスだけ変換する。Windows の node.exe を WSL から起動すると
# /mnt/c/... は C:\mnt\c\... と解釈されるため。
REPO_N="$REPO"
HERE_N="$HERE"
case "$NODE_BIN" in
  *.exe)
    if command -v wslpath >/dev/null 2>&1; then
      REPO_N=$(wslpath -w "$REPO")
      HERE_N=$(wslpath -w "$HERE")
    fi
    ;;
esac

"$NODE_BIN" --input-type=module -e '
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
const repo = process.argv[1], here = process.argv[2];
const { classifyCell } = await import(pathToFileURL(path.join(repo, ".claude/scripts/wt/slots.mjs")).href);
const { resolveLimits } = await import(pathToFileURL(path.join(repo, ".claude/scripts/wt/policy.mjs")).href);

const cases = JSON.parse(fs.readFileSync(path.join(here, "cases/cases.json"), "utf8"));
const expected = JSON.parse(fs.readFileSync(path.join(here, "expected/expected.json"), "utf8"));

// 抽出が空でも緑にならないよう、件数と対応を先に検査する。
if (cases.length === 0) { console.error("FAIL: cases が空"); process.exit(2); }
if (cases.length !== expected.length) { console.error("FAIL: cases と expected の件数が不一致"); process.exit(2); }
const byName = new Map(expected.map((e) => [e.name, e.expect]));

let failed = 0, ran = 0;
// 受入条件は「判定ループ」= 全ケースの評価だけで測る。出力（console.log）を
// 含めると計測が端末 I/O に支配され、閾値が環境で揺れる。評価と出力を分ける。
const outcomes = [];
const loopStart = process.hrtime.bigint();
for (const c of cases) {
  if (!byName.has(c.name)) { outcomes.push({ name: c.name, kind: "missing-expected" }); continue; }
  const want = byName.get(c.name);
  let got;
  if (c.fn === "classifyCell") got = classifyCell(c.input);
  else if (c.fn === "resolveLimits") got = resolveLimits(c.input);
  else { outcomes.push({ name: c.name, kind: "unknown-fn", fn: c.fn }); continue; }
  ran++;
  const diff = Object.keys(want).filter((k) => JSON.stringify(got[k]) !== JSON.stringify(want[k]));
  outcomes.push(diff.length ? { name: c.name, kind: "diff", diff, got, want } : { name: c.name, kind: "pass" });
}
const loopMs = Number(process.hrtime.bigint() - loopStart) / 1e6;

for (const o of outcomes) {
  if (o.kind === "pass") { console.log(`PASS     ${o.name}`); continue; }
  failed++;
  if (o.kind === "missing-expected") console.error(`FAIL: expected に ${o.name} が無い`);
  else if (o.kind === "unknown-fn") console.error(`FAIL: 未知の fn ${o.fn}`);
  else console.error(`FAIL     ${o.name}  ${o.diff.map((k) => `${k}: got=${JSON.stringify(o.got[k])} want=${JSON.stringify(o.want[k])}`).join(" / ")}`);
}

// 1 件も走らずに緑になる経路を塞ぐ。
if (ran !== cases.length) { console.error(`FAIL: 実行数 ${ran} が cases 数 ${cases.length} と一致しない`); process.exit(1); }
const BUDGET_MS = 50;
if (loopMs >= BUDGET_MS) {
  console.error(`FAIL     judgment-loop-budget  ${loopMs.toFixed(2)}ms >= ${BUDGET_MS}ms`);
  failed += 1;
} else {
  console.log(`PASS     judgment-loop-budget  ${loopMs.toFixed(2)}ms < ${BUDGET_MS}ms`);
}
console.log(`=== wt-slots: ${ran - failed} PASS / ${failed} FAIL (${ran} cases) ===`);
process.exit(failed ? 1 : 0);
' "$REPO_N" "$HERE_N"
