#!/bin/bash
# Replay the frozen oracle file against the live guard. PASS when every case matches.
set -u
REPO="${1:?usage: replay-oracle.sh <repo-root>}"
FIXTURE="$REPO/tests/fixtures/guard-oracle/cases.jsonl"
# Guard 5.5 fixture: a simulated worktree containing node_modules. Provisioned
# here (not committed) because the repo-wide .gitignore excludes node_modules/.
mkdir -p "$REPO/tests/fixtures/guard-oracle/wt-junction-sim/node_modules"
PASS=0; FAIL=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  id=$(printf '%s\n' "$line" | jq -r '.id')
  hook=$(printf '%s\n' "$line" | jq -r '.hook')
  stdin_json=$(printf '%s\n' "$line" | jq -c '.stdin')
  # {{REPO}} placeholder: lets a case reference a committed fixture path (e.g. a
  # simulated worktree with node_modules for Guard 5.5) portably across clones.
  stdin_json=${stdin_json//"{{REPO}}"/$REPO}
  exp_dec=$(printf '%s\n' "$line" | jq -r '.expected.decision')
  exp_sub=$(printf '%s\n' "$line" | jq -r '.expected.output_contains // ""')
  # tr -d '\r': Windows の jq は複数行出力を CRLF で終端するため、env が複数キーの
  # ケースでは中間行の値末尾に \r が残り「値が一致しない」偽動作になる（1 キーなら
  # 末尾改行ごと $() が剥がすため顕在化しない）。
  envargs=$(printf '%s\n' "$line" | jq -r '.env | to_entries | map("\(.key)=\(.value)") | .[]' 2>/dev/null | tr -d '\r')
  if [ -n "$envargs" ]; then
    out=$(printf '%s\n' "$stdin_json" | env $envargs bash "$REPO/$hook" 2>/dev/null)
  else
    out=$(printf '%s\n' "$stdin_json" | env -u SIDEKICK_STG_ENABLED bash "$REPO/$hook" 2>/dev/null)
  fi
  if [ -z "$out" ]; then obs="allow_silent"
  elif printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then obs="deny"
  elif printf '%s' "$out" | grep -q '"permissionDecision":"allow"'; then obs="allow_context"
  else obs="UNKNOWN"; fi
  ok=1
  [ "$obs" = "$exp_dec" ] || ok=0
  if [ -n "$exp_sub" ]; then printf '%s' "$out" | grep -qF "$exp_sub" || ok=0; fi
  if [ "$ok" -eq 1 ]; then PASS=$((PASS+1)); else
    FAIL=$((FAIL+1)); printf 'FAIL %s expected=%s observed=%s\n' "$id" "$exp_dec" "$obs"
  fi
done < "$FIXTURE"
printf '=== replay: %d PASS / %d FAIL ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
