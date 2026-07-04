#!/bin/bash
# =============================================================================
# 公式スキル鮮度 watch — ラッパーと公式 CLI の floor/availability drift 検知
# (weekly-inventory Step 5d / ADR-0027 決定4)
#
# 機械で分かる部分だけを担当する: 稼働 CLI のバージョンを読み、ccs がラップする
# 各公式 feature の version floor（hook-helpers の single source of truth）を
# 満たすかを判定する。新規公式スキルの検知・挙動変更の判断は機械化できないので
# news-upstream / 公式リリースノートを入力にする（SKILL.md Step 5d 参照）。
#
# fail-open (ADR-0027 決定3): バージョン検出不能・floor 不明は「利用可」に倒す
# （壊れたプローブでラッパーを無効化しない）。出力は人間可読サマリのみ・exit 0。
#
# Usage: .claude/skills/weekly-inventory/scripts/official-freshness.sh
# =============================================================================

HELPERS="$(cd "$(dirname "$0")/../../.." && pwd)/hooks/hook-helpers.sh"
if [ ! -f "$HELPERS" ]; then
  printf '公式鮮度 watch: hook-helpers.sh 不在（%s）— スキップ\n' "$HELPERS"
  exit 0
fi
# shellcheck source=/dev/null
. "$HELPERS"

CUR=$(ccs_claude_version)
printf '=== 公式スキル鮮度 watch（ADR-0027 決定4）===\n'
printf 'Claude Code CLI: %s\n' "${CUR:-検出不能（fail-open=利用可扱い）}"
printf '%s\n' '----------------------------------------'

BELOW=0
for f in $(ccs_official_features); do
  min=$(_ccs_official_min_version "$f")
  if ccs_official_available "$f"; then
    printf '  OK  %-18s floor %-8s 利用可\n' "$f" "${min:-?}"
  else
    printf '  ✗   %-18s floor %-8s 未達 — ラッパーは fallback 稼働。CLI 更新 or floor 見直しを検討\n' "$f" "${min:-?}"
    BELOW=$((BELOW + 1))
  fi
done

printf '%s\n' '----------------------------------------'
printf 'floor 未達: %s 件\n' "$BELOW"
printf '判断部（機械化不可）: 新規公式スキル・挙動変更は news-upstream / 公式リリースノートを照合し、\n'
printf '  ラッパー未対応の gap を Issue 化する（SKILL.md Step 5d）。\n'
exit 0
