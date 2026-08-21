#!/bin/bash
# =============================================================================
# check-merged-pr.sh — 「マージ済み PR のブランチへ追い足し push していないか」の判定
#
# 背景:
#   PR がマージされた後に同じブランチへ push しても、その差分は元 PR に反映されない。
#   push は成功し、リモートにもコミットが載るため一見成功に見えるが、ベースブランチには
#   永久に入らない（＝作業したつもりで消える）。規約（push 前に PR 状態を確認する）だけでは
#   守れないため、機械で判定する。
#
# 使い方:
#   check-merged-pr.sh <branch>
#
# 終了コード（呼び出し側が意味を解釈する）:
#   0 = push してよい（マージ済み PR が無い / 同ブランチに OPEN な PR が別途ある / ack 済み）
#   1 = ブロック対象（マージ済み PR があり、OPEN な PR は無い）
#   2 = 判定不能（gh が無い・未認証・API 失敗）。呼び出し側は fail-closed で扱う
#
# 呼び出し側（同じ判定の単一の正）:
#   - .claude/hooks/guard-bash.sh Guard 2.5（Claude の Bash 経由の push）
#   - .claude/githooks/pre-push ゲート0（人間・スクリプト経由の push）
#
# 例外（ack）: CONFIRM_PUSH_TO_MERGED=1 を付けて実行すると判定をスキップする。
#   環境変数を明示的に付ける形にしているのは、ゲートを外した事実をコマンド履歴に残すため。
# =============================================================================

set -u

BRANCH="${1:-}"

# ack: ゲートを意図的に外す（履歴に痕跡が残る）
if [ "${CONFIRM_PUSH_TO_MERGED:-}" = "1" ]; then
  exit 0
fi

# テストシーム（guard-oracle replay 用）: 0|1|2 のときだけ実 gh を呼ばずその終了コードを
# 返し、ネットワーク依存の判定を決定的に再生できるようにする。ゲートを外せる力は
# 上の CONFIRM_PUSH_TO_MERGED と同等以下（新しいバイパス経路にはならない）。
case "${SIDEKICK_TEST_MERGED_PR_RC:-}" in
  0|1|2) exit "$SIDEKICK_TEST_MERGED_PR_RC" ;;
esac

# ブランチが特定できないときは判定しない（呼び出し側が現在ブランチを解決して渡す責務）
if [ -z "$BRANCH" ]; then
  exit 0
fi

if ! command -v gh > /dev/null 2>&1; then
  exit 2
fi

merged=$(gh pr list --head "$BRANCH" --state merged --json number --jq 'length' 2>/dev/null)
if [ -z "$merged" ]; then
  # gh はあるが応答が得られない（未認証 / ネットワーク / API エラー）
  exit 2
fi

if [ "$merged" -eq 0 ] 2>/dev/null; then
  exit 0
fi

# マージ済み PR があっても、同じブランチに OPEN な PR が別途あるなら追い足しは正当
# （マージ後に同ブランチで新しい PR を開いて作業を続けているケース）。
open=$(gh pr list --head "$BRANCH" --state open --json number --jq 'length' 2>/dev/null)
if [ -z "$open" ]; then
  exit 2
fi
if [ "$open" -gt 0 ] 2>/dev/null; then
  exit 0
fi

exit 1
