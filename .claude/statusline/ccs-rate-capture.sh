#!/usr/bin/env bash
# ccs-rate-capture.sh — 文脈経済 budget-gate のデータ面（ADR-0024 決定2）
#
# Claude Code は statusLine の stdin JSON に公式 rate_limits（5h/7d の used_percentage + resets_at）を渡す。
# これは hook の stdin には来ないため、強制層 hook が読めるよう正準ファイルへ抜き出して保存する。
#
# 使い方（どちらか）:
#   A) パイプ前段にする — settings.json の statusLine.command を
#        "bash <path>/ccs-rate-capture.sh | bash <あなたの statusline>"
#      本スクリプトは stdin を素通しするので既存 statusline はそのまま動く。
#   B) 既存 statusline の中から呼ぶ — 入力 JSON を持っている箇所で
#        printf '%s' "$INPUT" | bash <path>/ccs-rate-capture.sh >/dev/null
#
# 設計（ADR-0024）:
#   - rate_limits は「全製品横断の合算 quota」かつグローバル値ゆえ % のみ保存（per-session 値は入れない）。
#   - rate_limits の知識（jq パス）はこの1箇所に閉じる。全フィールド // null 防御。
#   - 取得不能（fresh session / API-key / 旧版 / jq 無し）は異常でなく仕様 → 静かに継続（fail-open）。
#   - 原子的書込（tmp→mv）で部分読みを防ぐ。echo でなく printf（POSIX 安全・CLAUDE.md §3）。
#   - 出力ファイル既定: ~/.claude/.cache/ccs-rate-limits.json（CCS_CACHE_DIR で上書き可）。

INPUT=$(cat)

CACHE_DIR="${CCS_CACHE_DIR:-$HOME/.claude/.cache}"
OUT="$CACHE_DIR/ccs-rate-limits.json"

if command -v jq >/dev/null 2>&1; then
  mkdir -p "$CACHE_DIR" 2>/dev/null
  NOW=$(date +%s 2>/dev/null)
  # rate_limits が無くても全フィールド null で書く（reader は pct=null を「cap データ無し」と解釈）。
  printf '%s' "$INPUT" | jq -c --argjson now "${NOW:-0}" '
    { schema: 1, captured_at: $now,
      session_id: (.session_id // null),
      cc_version:  (.version // null),
      five_hour: { pct:       (.rate_limits.five_hour.used_percentage // null),
                   resets_at: (.rate_limits.five_hour.resets_at // null) },
      seven_day: { pct:       (.rate_limits.seven_day.used_percentage // null),
                   resets_at: (.rate_limits.seven_day.resets_at // null) } }' \
    > "$OUT.tmp" 2>/dev/null && mv -f "$OUT.tmp" "$OUT" 2>/dev/null
  rm -f "$OUT.tmp" 2>/dev/null
fi

# stdin を素通し（パイプ前段として使えるように）。
printf '%s' "$INPUT"
