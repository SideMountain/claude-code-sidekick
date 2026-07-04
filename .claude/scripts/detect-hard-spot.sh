#!/bin/bash
# =============================================================================
# detect-hard-spot.sh — deterministic force-flag for R2 難所 (ADR-0028 決定3)
#
# 難所かどうかの判定が prose 裁量である限り、標準モデルが難所を見落とすと
# R3 以降の敵対検証が丸ごとスキップされる。この決定的検査（パス・キーワードの
# grep）を前置し、ヒットした変更は *モデルの自己判定に関わらず* 難所として扱う
# (force-flag)。モデル判定は force-flag に「追加する方向のみ」許す（機械が難所と
# 言えば難所。機械が沈黙してもモデルが難所と判断すれば難所）。
#
# 共有配置の理由: この検査は auto-implement / review など *複数スキルから参照*
# される決定的ゲートである。per-skill の scripts/ に置くと同じ grep ロジックが
# 各スキルに重複し修正漏れの温床になる（diagnosis DRY）。単一ソースとして
# .claude/scripts/ に共有配置する。
#
# Output: ヒットごとに 1 行 "HARD_SPOT <番号>:<カテゴリ> — <根拠(パス or キーワード)>"。
#         ヒットなしなら "難所 force-flag なし" の 1 行。
# Exit code: 常に 0（advisory。判定の主体はモデル/スキュー側で、本検査は追加信号）。
#
# Usage: detect-hard-spot.sh [BASE_REF]
#   BASE_REF の解決は review/scripts/review-fitness.sh を踏襲（origin/HEAD →
#   origin/main → main）。branch に commit がある場合は committed range
#   "<base>...HEAD"、無い（HEAD==base）or base 解決不能の場合は working-tree
#   diff (git diff HEAD) にフォールバックする — 未 commit の作業も pre-commit
#   時点で拾えるようにするため（review-fitness の working-tree fallback と同旨）。
#
# POSIX 安全（CLAUDE.md §3 Lessons）: printf のみ（echo 不使用）/ jq 不使用
# （pure grep）/ LC_ALL=C 固定。
# =============================================================================

LC_ALL=C
export LC_ALL
set -u

# --- Resolve the diff range (review-fitness.sh を踏襲) -------------------------
BASE="${1:-}"
if [ -z "$BASE" ]; then
  BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@')
  [ -z "$BASE" ] && { git rev-parse --verify -q origin/main >/dev/null 2>&1 && BASE="origin/main"; }
  [ -z "$BASE" ] && { git rev-parse --verify -q main >/dev/null 2>&1 && BASE="main"; }
fi

# committed range は branch が base より先行しているときだけ。HEAD==base（新規
# branch で未 commit）や base 解決不能なら working-tree diff に落として拾う。
RANGE=""
if [ -n "$BASE" ] && git rev-parse --verify -q "$BASE" >/dev/null 2>&1; then
  if [ "$(git rev-parse "$BASE" 2>/dev/null)" != "$(git rev-parse HEAD 2>/dev/null)" ]; then
    RANGE="$BASE...HEAD"
  fi
fi

# 変更パス（追加/変更/削除/リネーム）。
_names() {
  if [ -n "$RANGE" ]; then
    git diff --name-only "$RANGE" 2>/dev/null
  else
    git diff --name-only HEAD 2>/dev/null
  fi
}

# 追加('+')/削除('-')された内容行。file ヘッダ（+++ / ---）は除く。
_diff_lines() {
  { if [ -n "$RANGE" ]; then
      git diff -U0 "$RANGE" 2>/dev/null
    else
      git diff -U0 HEAD 2>/dev/null
    fi
  } | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) '
}

NAMES=$(_names)
DIFFLINES=$(_diff_lines)

FINDINGS=""
add() { FINDINGS="${FINDINGS}$1"$'\n'; }

# --- Check A: ガード機構パス → カテゴリ4 --------------------------------------
# .claude/hooks/ .claude/githooks/ .claude/scripts/ settings*.json
while IFS= read -r p; do
  [ -z "$p" ] && continue
  add "HARD_SPOT 4:セキュリティ(ガード機構) — $p"
done <<EOF
$(printf '%s\n' "$NAMES" | grep -E '(^|/)\.claude/(hooks|githooks|scripts)/|(^|/)settings[^/]*\.json$' 2>/dev/null)
EOF

# --- Check B: スキーマ変更パス → カテゴリ1 ------------------------------------
# prisma/ migrations/ *.sql schema.prisma
while IFS= read -r p; do
  [ -z "$p" ] && continue
  add "HARD_SPOT 1:設計判断(スキーマ変更) — $p"
done <<EOF
$(printf '%s\n' "$NAMES" | grep -E '(^|/)prisma/|(^|/)migrations/|\.sql$|(^|/)schema\.prisma$' 2>/dev/null)
EOF

# --- Check C: 認可・信頼境界を示唆するパス名トークン → カテゴリ4 --------------
# auth middleware permission acl session token（大文字小文字無視・部分一致）
while IFS= read -r p; do
  [ -z "$p" ] && continue
  add "HARD_SPOT 4:セキュリティ(認可・信頼境界のパス名) — $p"
done <<EOF
$(printf '%s\n' "$NAMES" | grep -iE 'auth|middleware|permission|acl|session|token' 2>/dev/null)
EOF

# --- Check D: 安全設定キーの変更行 → カテゴリ4 --------------------------------
for kw in AUTO_MODE SIDEKICK_AUTO PROTECTED_BRANCHES DATABASE_URL; do
  if printf '%s\n' "$DIFFLINES" | grep -qE "$kw" 2>/dev/null; then
    add "HARD_SPOT 4:セキュリティ(設定キー変更) — $kw"
  fi
done

# --- Check E: 破壊的 DDL の変更行 → カテゴリ1 ---------------------------------
check_ddl() {  # $1=grep パターン, $2=表示キーワード
  if printf '%s\n' "$DIFFLINES" | grep -qiE "$1" 2>/dev/null; then
    add "HARD_SPOT 1:設計判断(破壊的DDL) — $2"
  fi
}
check_ddl 'DROP[[:space:]]+TABLE'  'DROP TABLE'
check_ddl 'DROP[[:space:]]+COLUMN' 'DROP COLUMN'
check_ddl 'ALTER[[:space:]]+TYPE'  'ALTER TYPE'
check_ddl 'RENAME[[:space:]]+TO'   'RENAME TO'

# --- Report（順序保持で重複行を除去）-----------------------------------------
if [ -n "$FINDINGS" ]; then
  printf '%s' "$FINDINGS" | awk 'NF && !seen[$0]++'
else
  printf '難所 force-flag なし\n'
fi
exit 0
