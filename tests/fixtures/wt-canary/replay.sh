#!/bin/bash
# =============================================================================
# replay.sh — Resource Governor の CLI 境界カナリア（ADR-0035 Phase 4B）
#
# 生の fixture（wt-slots / wt-concurrency）は slots.mjs の API を直接叩く。
# ここだけが with-slot.mjs の CLI 境界を実プロセスで通し、次の 3 点を見る:
#
#   1. 競合時の拒否 — 枠が埋まっているとき、短い取得期限で RESOURCE_BUSY(5)
#   2. 解放         — 保持側の終了後に、同じ index を再取得できる
#   3. 残骸なし     — 隔離した store 配下に ACTIVE な資源が残らない
#
# 有界化は wall 時間の閾値で行わない（runner の混雑で偽陰性になる）。
# 取得期限・holder の内部 deadline・自分の子だけの回収・workflow の
# timeout-minutes が境界を担う。wall は記録値としてのみ出力する。
#
# store と policy は suite root 配下へ隔離する。利用者の実 store・実 policy・
# OS 全体の tmp には触れない。
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
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v "$NODE_BIN" >/dev/null 2>&1 || { echo "FAIL: node が見つかりません: $NODE_BIN" >&2; exit 2; }

[ -f "$HERE/run.mjs" ] || { echo "FAIL: run.mjs が無い: $HERE/run.mjs" >&2; exit 2; }
[ -f "$REPO/.claude/scripts/wt/with-slot.mjs" ] || { echo "FAIL: with-slot.mjs が無い" >&2; exit 2; }

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
