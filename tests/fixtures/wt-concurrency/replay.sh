#!/bin/bash
# =============================================================================
# replay.sh — 並行性の回帰 4 ケース（ADR-0035 決定 10・Phase 3 分）
#
# 純粋関数では競合を再現できないため、この 4 点だけ実プロセスで確認する。
#
#   1. 上限 N に N+k 本を同時起動 → 成功数が正確に N（固定 cell の排他）
#   2. N=1 で回収と取得を競合 → 同時実行数が 1 を超えない（quarantine の占有計上）
#   3. 同一 stale cell への同時回収 → rename 成功は 1 つだけ（二重回収の防止）
#   4. SIGKILL 後に stale recovery で枠が戻る（finally 非経路の回収）
#
# 走査量は設定された slot 上限にのみ比例する。全 WT・全プロセスを走査しない。
#
# 使い方: replay.sh [--node <path>]
# Exit: 0 = 全件 PASS / 1 = 失敗あり / 2 = 実行不能
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
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v "$NODE_BIN" >/dev/null 2>&1 || { echo "FAIL: node が見つかりません: $NODE_BIN" >&2; exit 2; }

[ -f "$HERE/run.mjs" ] || { echo "FAIL: run.mjs が無い: $HERE/run.mjs" >&2; exit 2; }

# node へ渡すパスだけ変換する（理由は wt-slots/replay.sh と同じ）。
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

"$NODE_BIN" "$HERE_N/run.mjs" "$REPO_N"
