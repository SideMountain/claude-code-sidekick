#!/bin/bash
# =============================================================================
# distribution-gate.sh — fail-closed caller-side gate for distribution completeness
#
# Why this is a script and not three paragraphs in three SKILL.md files
# --------------------------------------------------------------------
# The decision this encodes is "may the caller proceed?", and the only safe
# default is no. Written as prose, each caller re-derives the mapping from the
# verifier's exit code to a stop/continue decision, and the failure mode is
# always the same one: an unanticipated status (the verifier is missing, the
# bootstrap half-succeeded, something returned 127) falls through the cases
# nobody wrote and the caller carries on as though the check had passed.
# A check that can be skipped by accident is not a check.
#
# So: one exit code, one meaning, and *every* path that is not a verified-clean
# tree is non-zero.
#
#   0  PROCEED — verifier ran and reported a complete distribution
#   3  STOP — companions missing (EVIDENCE_REQUIRED)
#   4  STOP — indeterminate: manifest absent, or not inside a git repo
#   5  STOP — the verifier itself is absent and no ref was given to restore it
#   6  STOP — bootstrap failed (object absent at ref / empty output / chmod / move)
#   7  STOP — the verifier exited with a status this gate does not recognise
#
# Callers must treat "not 0" as stop, not "3 or 4" as stop. The `*)` branch
# exists precisely because the interesting failures are the ones not enumerated.
#
# Usage:
#   distribution-gate.sh                      # verify only (e.g. /review Step 0)
#   distribution-gate.sh --repair-from <ref>  # bootstrap the verifier/manifest
#                                             # from <ref> if absent, then verify
#                                             # with repair (e.g. /adopt Step 6.6)
# =============================================================================

set -u

REPAIR_REF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repair-from) REPAIR_REF="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,38p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$ROOT" ]; then
  printf '[EVIDENCE_REQUIRED] git リポジトリの外で実行されました — 配布完結性を判定できません\n' >&2
  exit 4
fi
cd "$ROOT" || exit 4

VERIFIER=".claude/scripts/verify-distribution.sh"
MANIFEST=".claude/scripts/distribution-manifest.tsv"

_stop() {  # $1=exit code, $2...=message
  local code="$1"; shift
  printf '[EVIDENCE_REQUIRED] %s\n' "$*" >&2
  printf '=== distribution-gate: STOP (exit %s) — 取り込み/レビューを完了扱いにしないでください ===\n' "$code" >&2
  exit "$code"
}

# --- Bootstrap ---------------------------------------------------------------
# The verifier and its manifest are themselves companions, so the very failure
# they detect can remove them. Restoring from the release ref is allowed, but
# every step is checked: a bootstrap that half-works and leaves a zero-byte
# verifier behind would make the next run "succeed" while checking nothing.
#
# Writes to a temp path and moves into place, so an interrupted or failed
# restore never leaves a truncated file where a working one used to be.
_bootstrap() {  # $1=path
  local p="$1" tmp
  if ! git cat-file -e "${REPAIR_REF}:${p}" 2>/dev/null; then
    _stop 6 "${p} が ${REPAIR_REF} に存在しません（bootstrap 不可）。ref が正しいか、上流で撤去されていないか確認してください"
  fi
  tmp="${p}.ccs-bootstrap.$$"
  mkdir -p "$(dirname "$p")" || _stop 6 "$(dirname "$p") を作成できません"
  if ! git show "${REPAIR_REF}:${p}" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    _stop 6 "git show ${REPAIR_REF}:${p} に失敗しました"
  fi
  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    _stop 6 "${REPAIR_REF}:${p} の取り出し結果が空でした（空の検査器は「検査した」と見分けがつかないため配置しません）"
  fi
  if ! mv "$tmp" "$p"; then
    rm -f "$tmp"
    _stop 6 "${p} への配置に失敗しました"
  fi
  case "$p" in
    *.sh)
      if ! chmod +x "$p"; then
        _stop 6 "${p} の実行権限付与に失敗しました"
      fi
      ;;
  esac
  printf '  bootstrapped: %s (from %s)\n' "$p" "$REPAIR_REF"
}

if [ -n "$REPAIR_REF" ]; then
  [ -f "$VERIFIER" ] || _bootstrap "$VERIFIER"
  [ -f "$MANIFEST" ] || _bootstrap "$MANIFEST"
fi

if [ ! -f "$VERIFIER" ]; then
  _stop 5 "${VERIFIER} が存在しません — 配布完結性を検査できないため、結果を「問題なし」と読めません（/adopt-sidekick-update で取り込むか、--repair-from <tag> で復元してください）"
fi

# --- Run the verifier --------------------------------------------------------
# Invoked through `bash` on purpose: a companion restored by `git show` can
# arrive without its executable bit, and a 126 from that would be reported as a
# mysterious unexpected status rather than the completeness answer we need.
if [ -n "$REPAIR_REF" ]; then
  bash "$VERIFIER" --repair-from "$REPAIR_REF"
else
  bash "$VERIFIER"
fi
VERIFY_STATUS=$?

case "$VERIFY_STATUS" in
  0)
    echo "=== distribution-gate: PROCEED — 配布は完結しています ==="
    exit 0
    ;;
  3)
    _stop 3 "参照先の companion が欠落しています（上のリストを解消するまで、該当スキルは沈黙のまま dimension を落とします）"
    ;;
  4)
    _stop 4 "判定不能（manifest 欠落 等）— 「欠落なし」とは読めません"
    ;;
  *)
    _stop 7 "検査器が想定外の終了コード ${VERIFY_STATUS} を返しました（126=実行不可 / 127=not found / その他）。想定外は成功ではありません"
    ;;
esac
