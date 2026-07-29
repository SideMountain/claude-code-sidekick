#!/bin/bash
# =============================================================================
# verify-migration-stg.sh — migration の STG トランザクション dry-run（検知層）
#
# STG 適用の承認（H19）を依頼する前に実行し、migration が参照するオブジェクトの
# 現存を実 DB（第一級の現在状態オラクル・current-state-oracle.md）で機械検証する。
# BEGIN → 適用 → ROLLBACK のため STG に永続変更は残らない。
# 背景: 追記型履歴では時点根拠 ≠ 現在の真 — 過去の migration に存在したテーブルが
# 現在も在る保証はなく、撤去済みオブジェクトへの DDL は適用時（42P01）に初めて
# 発覚する。適用「前」に同じエラーを機械で捕まえるのが本スクリプト。
#
# Usage:
#   STG_DB_URL='postgresql://...' .claude/scripts/verify-migration-stg.sh <path/to/migration.sql>
#
# 位置づけ: ROLLBACK 保証のため STG SELECT 相当（自動実行可）。ただし出力される
# 接続先ホストを毎回確認すること。PRD_DB_URL が環境にあれば同一ホストを拒否する。
#
# 制約（安全側に中断するケース）:
#   - migration 内にトランザクション制御文（COMMIT/BEGIN/ROLLBACK 等）がある
#     → wrapper の ROLLBACK を突き破り実適用になるため検証しない
#   - CREATE INDEX CONCURRENTLY / ALTER TYPE ... ADD VALUE / VACUUM / REINDEX
#     → トランザクション内で実行不可のため検証しない（手動レビュー + 適用時注意）
#   ※ 判定は SQL コメントと dollar-quoted 関数本体を除去した後に行う
#     （関数内の BEGIN/END・コメント内のテーブル名言及で誤検知しない）
#
# POSIX 安全: printf のみ / LC_ALL=C。秘密情報: 接続文字列全体は出力しない
# （表示はホスト部のみ）。
# =============================================================================

LC_ALL=C
export LC_ALL
set -u

die() { printf 'ABORT: %s\n' "$1" >&2; exit 1; }

FILE="${1:-}"
[ -n "$FILE" ] || die "Usage: STG_DB_URL='postgresql://...' $0 <migration.sql>"
[ -f "$FILE" ] || die "ファイルが見つからない: $FILE"
case "$FILE" in
  *' '*|*'	'*) die "空白を含むパスは非対応（psql \\i の制約）。パスを変えて再実行" ;;
esac

[ -n "${STG_DB_URL:-}" ] || die "STG_DB_URL が未設定。フォールバックしない — STG の接続文字列を環境変数で明示して再実行する"

command -v psql >/dev/null 2>&1 || die "psql が見つからない（PATH を確認）"
command -v perl >/dev/null 2>&1 || die "perl が見つからない（コメント除去に必要。Git Bash / ubuntu には標準搭載）"

# --- 接続先の可視化（秘密は出さない: ホスト部のみ）--------------------------
host_of() { printf '%s' "$1" | sed -E 's#^[a-zA-Z]+://([^@/]*@)?([^/?:]+).*#\2#'; }
STG_HOST=$(host_of "$STG_DB_URL")
printf '接続先ホスト: %s\n' "$STG_HOST"

# PRD 誤爆ガード: PRD_DB_URL が環境にあり同一ホストなら拒否（安全側）
if [ -n "${PRD_DB_URL:-}" ] && [ "$(host_of "$PRD_DB_URL")" = "$STG_HOST" ]; then
  die "STG_DB_URL のホストが PRD_DB_URL と一致。PRD への dry-run は行わない"
fi

# --- トランザクション安全性ガード ---------------------------------------------
# コメント（-- と /* */）と dollar-quoted 文字列（$$...$$ / $tag$...$tag$）を
# 除去してから判定する。関数本体の BEGIN/END は制御文ではないため除外が必須。
STRIPPED=$(perl -0777 -pe '
  s{\$([A-Za-z_][A-Za-z0-9_]*|)\$.*?\$\1\$}{}gs;  # dollar-quoted bodies（空分岐で $$ にも後方参照を効かせる）
  s{/\*.*?\*/}{}gs;                                # block comments
  s{--[^\n]*}{}g;                                  # line comments
' "$FILE") || die "コメント除去に失敗: $FILE"

if printf '%s\n' "$STRIPPED" | grep -qiE '(^|;)[[:space:]]*(commit|rollback|begin|start[[:space:]]+transaction|end[[:space:]]+transaction)\b'; then
  die "migration 内にトランザクション制御文がある。wrapper の ROLLBACK を突き破るため dry-run 不可 → 手動レビューで担保する"
fi

if printf '%s\n' "$STRIPPED" | grep -qiE 'create[[:space:]]+(unique[[:space:]]+)?index[[:space:]]+concurrently|alter[[:space:]]+type[[:space:]]+[^;]*add[[:space:]]+value|(^|;)[[:space:]]*(vacuum|reindex)\b'; then
  die "トランザクション内で実行できない文を含む（CONCURRENTLY / ADD VALUE / VACUUM / REINDEX）。dry-run 不可 → 手動レビューで担保する"
fi

# --- 実行: BEGIN → \i migration → ROLLBACK -----------------------------------
FILE_ABS=$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")
# Windows ネイティブ psql は /c/... 形式を解せないため C:/... に変換する
command -v cygpath >/dev/null 2>&1 && FILE_ABS=$(cygpath -m "$FILE_ABS")

printf 'dry-run 実行中: %s\n' "$FILE"
# オプションは URL（位置引数）より前に置く — Windows ネイティブ psql は
# 位置引数より後ろのオプションを無視するため（ON_ERROR_STOP が無効化される）
printf 'BEGIN;\n\\i %s\nROLLBACK;\n' "$FILE_ABS" | psql -X -q -v ON_ERROR_STOP=1 "$STG_DB_URL"
RC=$?

if [ "$RC" -eq 0 ]; then
  printf 'PASS: %s は現在の STG スキーマに対して適用可能（ROLLBACK 済み・永続変更なし）\n' "$FILE"
else
  printf 'FAIL(exit %s): 上記 psql エラーを確認。42P01 等は「参照先が現存しない」候補 — 参照する全オブジェクトを current-state-oracle.md のオラクルで再確認する\n' "$RC" >&2
  exit "$RC"
fi
