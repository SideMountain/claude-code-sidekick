#!/bin/bash
# =============================================================================
# cleanup-worktrees.sh — マージ済み worktree の掃除（リンク共有事故の対策込み）
#
# 手作業の worktree 掃除には2つの事故モードがある:
#   A. リンク共有（Windows junction / POSIX symlink）した node_modules を
#      リンクと判定できないまま再帰削除し、共有先の実体を巻き込む
#   B. 消してよい worktree の判定（未push・未コミット・マージ済み）を目視に頼り、
#      未マージの作業や再生成できないローカル設定（.env.* 等）ごと消す
#
# 本スクリプトが機械化するもの:
#   1. サーベイ  — 未push / 未コミット / マージ済みか を worktree ごとに判定
#   2. 判定      — node_modules がリンクか実体か
#                  （Windows は fsutil reparsepoint が決定的。PowerShell の
#                   (Get-Item).LinkType は空文字を返す環境があり判定に使えない）
#   3. 撤去      — リンクは reparse point / symlink だけ外す（target へ再帰しない）
#   4. 二重確認  — 撤去できたかを [ -e ] で確認してから次へ進む
#   5. 健全性検査 — メインWS の共有 store を「存在」でなく「内容」で前後比較する
#                  （存在チェックは破壊されていても true を返しうる）
#
# 既定は dry-run。--apply を付けたときだけ削除する。
# guard-bash.sh Guard 5.5（node_modules が残る worktree の remove を deny）と
# 同じ安全順序（①リンク/実体の除去 → ②消失確認 → ③worktree remove）を実装する。
#
# Usage:
#   .claude/scripts/cleanup-worktrees.sh                     # サーベイのみ（安全）
#   .claude/scripts/cleanup-worktrees.sh --apply             # マージ済みを削除
#   .claude/scripts/cleanup-worktrees.sh --apply --keep e2e,smoke
#   .claude/scripts/cleanup-worktrees.sh --base origin/main  # マージ判定の基準を明示
#
# 削除しないもの（自動除外）:
#   - メインワークスペース
#   - 未push コミットがある / 追跡ファイルに変更がある worktree
#   - 基準ブランチにマージされていない worktree
#   - .env.* 等の再生成できないローカル設定を持つ worktree
#   - --keep で明示されたもの
# =============================================================================

set -u

APPLY=0
KEEP=""
BASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --keep) shift; KEEP="${1:-}" ;;
    --base) shift; BASE="${1:-}" ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'not a git repository\n' >&2; exit 2;
}
cd "$REPO_ROOT" || exit 2

# メインワークスペースの解決。--show-toplevel は「実行した worktree」を返すため、
# worktree の中から実行すると main を削除対象に含めてしまう。
# --git-common-dir は worktree から実行しても常に main の .git を指すので、その親が main。
MAIN_WS=$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd)")
[ -d "$MAIN_WS" ] || { printf 'main workspace を解決できません\n' >&2; exit 2; }

# 比較用に表記を揃える。Windows では git worktree list が "C:/Users/..." を返し、
# bash の pwd は "/c/Users/..." を返すため、素の文字列比較ではメインWS を除外できない
# （取り違えると本体を消す）。cygpath が無い環境（POSIX）はそのまま。
norm_path() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
MAIN_WS_CMP=$(norm_path "$MAIN_WS")
MAIN_NAME=$(basename "$MAIN_WS")

# マージ判定の基準ブランチ。--base 指定 > origin/release/stg（STG 運用）> origin/main
if [ -z "$BASE" ]; then
  if git rev-parse -q --verify origin/release/stg >/dev/null 2>&1; then
    BASE=origin/release/stg
  else
    BASE=origin/main
  fi
fi

# --- 共有 store の健全性を「内容」で測る（存在チェックは信用しない） ---
# 測るのは常にメインWS の node_modules（リンク共有先＝壊れると全体が死ぬ実体）。
# node_modules を持たないリポジトリでは "absent" 同士の比較になり、単に素通しする。
store_fingerprint() {
  local nm="$MAIN_WS/node_modules" bins entries
  [ -e "$nm" ] || { printf 'absent'; return; }
  bins=$(ls "$nm/.bin" 2>/dev/null | grep -c .)
  entries=$(ls "$nm" 2>/dev/null | grep -c .)
  printf 'bin=%s entries=%s' "$bins" "$entries"
}

BEFORE=$(store_fingerprint)
printf '=== shared store (before): %s / merge base: %s ===\n' "$BEFORE" "$BASE"

git fetch -q origin 2>/dev/null || true

is_kept() {
  case ",$KEEP," in *",$1,"*) return 0 ;; esac
  return 1
}

# --- 1. サーベイ ---
printf '\n%-34s %-14s %-8s %-6s %-9s %s\n' "WORKTREE" "NODE_MODULES" "unpushed" "dirty" "merged" "VERDICT"
TARGETS=""
while IFS= read -r wt; do
  [ -z "$wt" ] && continue
  [ "$(norm_path "$wt")" = "$MAIN_WS_CMP" ] && continue
  name=$(basename "$wt")
  short=${name#"$MAIN_NAME"-}

  branch=$(git -C "$wt" branch --show-current 2>/dev/null)
  if [ -z "$branch" ]; then
    printf '%-34s %-14s %-8s %-6s %-9s %s\n' "$short" "-" "-" "-" "-" "SKIP (no branch / prunable)"
    continue
  fi

  unpushed=$(git -C "$wt" log --oneline "origin/$branch..$branch" 2>/dev/null | grep -c .)
  dirty=$(git -C "$wt" status --porcelain 2>/dev/null | grep -cv '^??')
  if git merge-base --is-ancestor "$branch" "$BASE" 2>/dev/null; then merged=YES; else merged=NO; fi

  # node_modules の正体（リンクか実体か）。POSIX symlink → Windows junction → 実体の順で判定。
  nm="$wt/node_modules"
  if [ ! -e "$nm" ]; then
    kind="absent"
  elif [ -L "$nm" ]; then
    kind="symlink"
  elif fsutil reparsepoint query "$(cygpath -w "$nm" 2>/dev/null || printf '%s' "$nm")" >/dev/null 2>&1; then
    kind="junction"
  else
    kind="real-dir"
  fi

  # 再生成できないローカル設定を持つ worktree は自動的に残す。gitignore されたファイルは
  # dirty 判定に現れないため、気づかず消える経路になる（.env.* の実トークン等）。
  localcfg=$(ls "$wt"/.env.* 2>/dev/null | grep -v '\.example$' | grep -c .)

  verdict="DELETE"
  is_kept "$short" && verdict="KEEP (--keep)"
  [ "$localcfg" -ne 0 ] && verdict="KEEP (local env: $localcfg)"
  [ "$unpushed" -ne 0 ] && verdict="KEEP (unpushed=$unpushed)"
  [ "$dirty" -ne 0 ] && verdict="KEEP (dirty=$dirty)"
  [ "$merged" = "NO" ] && verdict="KEEP (not merged)"

  printf '%-34s %-14s %-8s %-6s %-9s %s\n' "$short" "$kind" "$unpushed" "$dirty" "$merged" "$verdict"
  [ "$verdict" = "DELETE" ] && TARGETS="$TARGETS$wt|$kind
"
done <<EOF
$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}')
EOF

if [ "$APPLY" -ne 1 ]; then
  printf '\n(dry-run) 削除するには --apply を付けて再実行する\n'
  exit 0
fi

# --- 2. node_modules の撤去（リンクはリンクだけ・実体は再帰削除） ---
printf '\n=== removing node_modules ===\n'
printf '%s' "$TARGETS" | while IFS='|' read -r wt kind; do
  [ -z "$wt" ] && continue
  nm="$wt/node_modules"
  case "$kind" in
    absent) continue ;;
    symlink)
      unlink "$nm" 2>/dev/null || rm "$nm" 2>/dev/null
      if [ -e "$nm" ]; then
        printf 'ABORT: symlink が残っています: %s\n' "$nm" >&2
        exit 1
      fi
      printf 'unlinked  %s\n' "$(basename "$wt")"
      ;;
    junction)
      win=$(cygpath -w "$nm" 2>/dev/null || printf '%s' "$nm")
      powershell -NoProfile -Command "[System.IO.Directory]::Delete('$win', \$false)" 2>/dev/null \
        || cmd //c rmdir "$win" 2>/dev/null
      if [ -e "$nm" ]; then
        printf 'ABORT: junction が残っています: %s\n' "$nm" >&2
        printf '  再帰削除に進むと共有 store を巻き込むため中断します。\n' >&2
        exit 1
      fi
      printf 'unlinked  %s\n' "$(basename "$wt")"
      ;;
    real-dir)
      # 長パス対応かつリンクを辿らない削除。node が無い環境は rm -rf に fallback
      # （kind=real-dir 確定後なのでリンク巻き込みはない）。
      if command -v node >/dev/null 2>&1; then
        node -e "require('fs').rmSync(process.argv[1],{recursive:true,force:true})" "$nm" 2>/dev/null
      else
        rm -rf "$nm" 2>/dev/null
      fi
      [ -e "$nm" ] && { printf 'WARN: 削除しきれず: %s\n' "$nm" >&2; continue; }
      printf 'removed   %s\n' "$(basename "$wt")"
      ;;
  esac
done

# --- 3. 撤去後に共有 store を再検査（ここで壊れていたら worktree は消さない） ---
AFTER_NM=$(store_fingerprint)
printf '\n=== shared store (after node_modules removal): %s ===\n' "$AFTER_NM"
if [ "$AFTER_NM" != "$BEFORE" ]; then
  printf 'ABORT: 共有 store の内容が変化しました（before=%s after=%s）。\n' "$BEFORE" "$AFTER_NM" >&2
  printf '  worktree の削除は中止します。依存を install し直して復旧してください。\n' >&2
  exit 1
fi

# --- 4. worktree 削除（node_modules 除去済みなので Guard 5.5 の安全順序を満たす） ---
printf '\n=== removing worktrees ===\n'
printf '%s' "$TARGETS" | while IFS='|' read -r wt kind; do
  [ -z "$wt" ] && continue
  if git worktree remove --force "$wt" 2>/dev/null; then
    printf 'removed   %s\n' "$(basename "$wt")"
  else
    printf 'WARN: remove 失敗（ハンドル保持の可能性）: %s\n' "$wt" >&2
  fi
done
git worktree prune -v

AFTER=$(store_fingerprint)
printf '\n=== shared store (final): %s ===\n' "$AFTER"
[ "$AFTER" = "$BEFORE" ] && printf 'OK: 共有 store は無傷\n' || {
  printf 'ABORT: 共有 store が変化しました（before=%s after=%s）\n' "$BEFORE" "$AFTER" >&2
  exit 1
}
