#!/bin/bash
# =============================================================================
# verify-release-notes.sh — deterministic gate for /release notes (診断 v2)
#
# /release の温度感伝達（ADR-0009）は「title prefix + body banner + severity
# マーカー」の3点一致に依存する。この一致は今まで references/release-format-spec.md
# を人が Read して手で合わせる注意力頼みだった。severity マーカーがズレると
# /inventory・/adopt-sidekick-update の機械検知（第一ソース）が壊れ、下流 PJ が
# リリース温度感を誤認する。この検査を gh release create の直前と /release Step 0
# に前置し、機械で分かる不一致は LLM に判定させない（決定的ゲート）。
#
# アンカーは references/release-format-spec.md の正確な文字列を使う:
#   severity マーカー : `> severity: {critical|standard|enhancement}`
#   title prefix      : `[CRITICAL]` / (なし) / `[ENHANCEMENT]`
#   body banner       : `**CRITICAL**` / (なし) / `**ENHANCEMENT**`
#   必須セクション    : ## Highlights / ## Changes / ## 変更された設計判断 (ADR)
#                       / ## 変更された rules / ## 変更された skills / Full Changelog
# 絵文字（⚠️ / 💡）は環境差でズレうるためアンカーにしない。ASCII/語トークンを使う。
#
# サブコマンド:
#   notes <severity> <title> <body-file>
#     GitHub Release notes が format-spec に一致するか検証（3点一致 + 必須節）。
#     不一致ごとに "[FAIL] <項目> — <理由>" を stdout に 1 行。
#     1 件でも不一致 → exit 1 / 全一致 → "[OK] ..." + exit 0。
#   unreleased [changelog-path]  (既定 CHANGELOG.md)
#     [Unreleased] セクションに実項目（`- ` 箇条書き）があるか検証。
#     空 → "[FAIL] ..." + exit 1 / 非空 → "[OK] ..." + exit 0。
#     ファイル不在は fail-open（[SKIP] + exit 0。CHANGELOG を持たない PJ 向け）。
#
# fail-open の対象は CHANGELOG 不在（unreleased）のみ。body-file 不在・引数不足・
# 不正 severity は「使い方エラー」= exit 2 + usage（release 手順のミスは可視化）。
#
# POSIX 安全（CLAUDE.md §3 Lessons）: printf のみ（echo 不使用）/ jq 不使用
# （pure grep/sed/awk）/ grep には 2>/dev/null / LC_ALL=C 固定。
# =============================================================================

LC_ALL=C
export LC_ALL
set -u

usage() {
  printf 'Usage:\n' >&2
  printf '  verify-release-notes.sh notes <severity> <title> <body-file>\n' >&2
  printf '  verify-release-notes.sh unreleased [changelog-path]\n' >&2
  printf '\n  <severity>: critical | standard | enhancement\n' >&2
}

FAILS=""
add_fail() { FAILS="${FAILS}[FAIL] $1"$'\n'; }

# --- サブコマンド: notes -----------------------------------------------------
do_notes() {
  severity="${1:-}"
  title="${2:-}"
  body_file="${3:-}"

  if [ -z "$severity" ] || [ -z "$title" ] || [ -z "$body_file" ]; then
    printf '[ERROR] 引数不足（severity / title / body-file すべて必須）\n' >&2
    usage
    exit 2
  fi
  case "$severity" in
    critical|standard|enhancement) ;;
    *)
      printf '[ERROR] 不正な severity: %s\n' "$severity" >&2
      usage
      exit 2
      ;;
  esac
  if [ ! -f "$body_file" ]; then
    printf '[ERROR] body-file が存在しない: %s\n' "$body_file" >&2
    usage
    exit 2
  fi

  # 1. severity マーカー（body 冒頭の blockquote 行・機械検知の第一ソース）
  # 行頭 '> severity:' の blockquote だけを見る（`^[[:space:]]*>`）。prose 本文や
  # Changes 転記に紛れた "severity: critical" 文字列は `>` で始まらないので拾わない
  # （位置非依存だと prose が本物マーカーを仮面化 / 誤マッチする）。-m1 で最初の1件。
  present=$(grep -m1 -oE '^[[:space:]]*>[[:space:]]*severity:[[:space:]]*(critical|standard|enhancement)' "$body_file" 2>/dev/null \
    | sed -E 's/.*severity:[[:space:]]*//')
  if [ -z "$present" ]; then
    add_fail "severity マーカー — body に '> severity: ${severity}' が無い（機械検知の第一ソース欠落）"
  elif [ "$present" != "$severity" ]; then
    add_fail "severity マーカー — body のマーカーは '${present}' だが引数は '${severity}'（3 点不一致）"
  fi

  # 2. title prefix（format-spec Title フォーマット表・prefix はバージョンより前）
  # 要約部（em dash `—` 以降）に出る語 [CRITICAL]/[ENHANCEMENT] を prefix と誤認しない
  # よう、title の prefix 部（`—` より前・無ければ title 全体）だけを見る。
  title_prefix="${title%%—*}"
  case "$severity" in
    critical)
      printf '%s' "$title_prefix" | grep -Fq '[CRITICAL]' \
        || add_fail "title prefix — critical だが title に [CRITICAL] prefix が無い"
      ;;
    enhancement)
      printf '%s' "$title_prefix" | grep -Fq '[ENHANCEMENT]' \
        || add_fail "title prefix — enhancement だが title に [ENHANCEMENT] prefix が無い"
      ;;
    standard)
      if printf '%s' "$title_prefix" | grep -Fq '[CRITICAL]' \
        || printf '%s' "$title_prefix" | grep -Fq '[ENHANCEMENT]'; then
        add_fail "title prefix — standard だが title に [CRITICAL]/[ENHANCEMENT] prefix がある（severity 不整合）"
      fi
      ;;
  esac

  # 3. body banner（format-spec Body Banner 節・banner は blockquote 行）
  # 行頭 '> ...**CRITICAL**...' の blockquote だけを banner と見なす。Changes 本文の
  # `- ... **CRITICAL** ...`（strong 強調）は `>` 行でないので banner と誤認しない
  # （位置非依存だと banner 書き忘れが本文の強調ですり抜け / standard の enhancement
  # 同梱説明で誤 fail する）。
  case "$severity" in
    critical)
      grep -qE '^[[:space:]]*>.*\*\*CRITICAL\*\*' "$body_file" 2>/dev/null \
        || add_fail "banner — critical だが body 冒頭に **CRITICAL** banner（blockquote）が無い"
      ;;
    enhancement)
      grep -qE '^[[:space:]]*>.*\*\*ENHANCEMENT\*\*' "$body_file" 2>/dev/null \
        || add_fail "banner — enhancement だが body 冒頭に **ENHANCEMENT** banner（blockquote）が無い"
      ;;
    standard)
      if grep -qE '^[[:space:]]*>.*\*\*(CRITICAL|ENHANCEMENT)\*\*' "$body_file" 2>/dev/null; then
        add_fail "banner — standard だが body に **CRITICAL**/**ENHANCEMENT** banner（blockquote）が残っている（下流誤検知の原因）"
      fi
      ;;
  esac

  # 4. 必須セクション（format-spec Body 必須セクション・行頭見出しに限定）
  # `^` アンカーで行頭見出しの存在を確認する。既知の限界: fenced code block（```）内に
  # 出る行頭見出し文字列も pass 扱いになる（fence 状態を追わない）。実見出しゼロで
  # code block 例だけの notes は異常系で現実性が低いため、fence 追跡は入れない
  # （過剰な機械化を避ける）。行頭でない prose 中の見出し文字列は非 pass。
  while IFS='|' read -r _name _pat; do
    [ -z "$_name" ] && continue
    grep -qE "$_pat" "$body_file" 2>/dev/null \
      || add_fail "必須セクション — '${_name}' が body に行頭見出しとして無い"
  done <<'SECS'
## Highlights|^## Highlights
## Changes|^## Changes
## 変更された設計判断 (ADR)|^## 変更された設計判断
## 変更された rules|^## 変更された rules
## 変更された skills|^## 変更された skills
Full Changelog|^[[:space:]]*\*\*Full Changelog
SECS

  if [ -n "$FAILS" ]; then
    printf '%s' "$FAILS"
    exit 1
  fi
  printf '[OK] release notes は format-spec に一致\n'
  exit 0
}

# --- サブコマンド: unreleased ------------------------------------------------
do_unreleased() {
  changelog="${1:-CHANGELOG.md}"

  if [ ! -f "$changelog" ]; then
    printf '[SKIP] %s 不在\n' "$changelog"
    exit 0
  fi

  # [Unreleased] 見出しから次の H2 見出し（`## ...`・or EOF）までの `- ` 箇条書きを
  # 数える。block を閉じるのは `^## `（角括弧の有無を問わない任意の H2）— `## [0.1.0]`
  # だけでなく書式ドリフトの `## 0.1.0` でも閉じ、旧版の項目を誤計上しない（P5）。
  # `### Added` 等の小見出し（`^### `）は `^## ` にマッチせず block を閉じない。
  # プレースホルダ箇条書き（「なし」「まだ〜」「N/A」「TBD」「none」で始まる・括弧付き
  # 許容）は実項目と見なさない（空リリースを誤って通さない・P4）。
  count=$(awk '
    /^## \[Unreleased\]/ { inblock=1; next }
    inblock && /^## /    { inblock=0 }
    inblock && /^- / {
      v = $0
      sub(/^- */, "", v)
      sub(/^（/, "", v); sub(/^\(/, "", v)   # 括弧はリテラルで除去（LC_ALL=C で全角の文字クラスは壊れる）
      sub(/^[[:space:]]*/, "", v)
      if (v !~ /^(なし|まだ|N\/A|TBD|[Nn]one|N\.A)/) c++
    }
    END { print c+0 }
  ' "$changelog" 2>/dev/null)

  if [ "${count:-0}" -gt 0 ]; then
    printf '[OK] [Unreleased] に %s 件の項目\n' "$count"
    exit 0
  fi
  printf '[FAIL] [Unreleased] が空 — リリースする変更がない\n'
  exit 1
}

# --- dispatch ----------------------------------------------------------------
cmd="${1:-}"
case "$cmd" in
  notes)      shift; do_notes "$@" ;;
  unreleased) shift; do_unreleased "$@" ;;
  *)          usage; exit 2 ;;
esac
