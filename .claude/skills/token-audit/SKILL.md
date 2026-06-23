---
name: token-audit
description: "トークン経済の検知層。常駐コンテキストの footprint（行数・文字数・推定トークン）を計測し、汚染・肥大・重複・path-scope 余地を検出する。実 cap 消費の計測プロトコルも提供。"
user-invocable: true
allowed-tools: "Read Grep Glob Bash"
---

# /token-audit — 常駐コンテキストの計測と汚染検知

文脈経済（ADR-0023 / `rules/context-economy.md`）の**検知層**。
「今いくら常駐しているか」を可視化し、削減候補を提案する。read-only（自動修正はしない）。

## 実行方式

軽量なら直接実行。メインコンテキストを汚したくない場合は Agent で隔離し、Return Contract のサマリだけ返す。

## Step 1: 常駐 footprint の計測

セッション開始時に常駐ロードされる主要ファイルを計測する。

```bash
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SLUG=$(echo "$ROOT" | sed 's|/|-|g')
MEM="$HOME/.claude/projects/$SLUG/memory/MEMORY.md"

printf "%-46s %8s %8s\n" "FILE" "LINES" "CHARS"; printf '%.0s-' {1..64}; echo
m(){ [ -f "$1" ] && printf "%-46s %8d %8d\n" "$2" "$(wc -l <"$1")" "$(wc -m <"$1")" || printf "%-46s %8s\n" "$2" "(none)"; }

m "$ROOT/CLAUDE.md" "CLAUDE.md"
m "$ROOT/CLAUDE.local.md" "CLAUDE.local.md"
# rules: path-scoped（paths: frontmatter）は常駐外なので除外して集計
for r in "$ROOT"/.claude/rules/*.md; do
  [ -f "$r" ] || continue
  head -5 "$r" | grep -qE "^paths:" && continue   # path-scoped はスキップ
  m "$r" "rules/$(basename "$r")"
done
m "$ROOT/.claude/brain/thinking.md" "PJ brain"
m "$HOME/.claude/brain/thinking.md" "personal brain"
m "$MEM" "auto-memory MEMORY.md"

# 常駐合計（path-scoped rule を除く）
SUM=$( { cat "$ROOT/CLAUDE.md" "$ROOT/CLAUDE.local.md" "$ROOT/.claude/brain/thinking.md" "$HOME/.claude/brain/thinking.md" "$MEM" 2>/dev/null
  for r in "$ROOT"/.claude/rules/*.md; do head -5 "$r" | grep -qE "^paths:" || cat "$r"; done 2>/dev/null; } | wc -m)
echo; echo "常駐合計（path-scoped 除く）: ${SUM} 文字  ≈ $((SUM*65/100))〜$((SUM*75/100)) トークン（推測・日本語混在）"
```

> 推定トークンは日本語混在 markdown で char×0.65〜0.75 の概算。**正確値ではない**（確度: 文字数=確認済み / トークン=推測）。

## Step 2: 汚染・肥大・重複の検知

```bash
echo "=== 200 行超過（常駐肥大）==="
for f in "$ROOT/CLAUDE.md" "$ROOT/.claude/rules"/*.md "$ROOT/.claude/brain/thinking.md" "$MEM"; do
  [ -f "$f" ] || continue; n=$(wc -l <"$f"); [ "$n" -gt 200 ] && echo "  $n行: ${f#$ROOT/}"
done
echo "=== path-scope 余地（常駐だが特定領域専用の疑い：db/deploy/git 等）==="
grep -lLE "^paths:" "$ROOT"/.claude/rules/{database,deploy-strategy,git-strategy}.md 2>/dev/null
echo "=== skill description 常駐量 ==="
n=0; t=0; for s in "$ROOT"/.claude/skills/*/SKILL.md; do
  [ -f "$s" ] || continue; d=$(awk -F'description:' '/^description:/{print $2; exit}' "$s"); t=$((t+${#d})); n=$((n+1)); done
echo "  skill $n 本 / description 合計 ${t} 文字"
```

検知観点（手動判断）:
- **重い常駐 rule**: メタ文書（知識マップ等）で実作業中ほぼ不要なものは「遅延ロード / path-scope」候補。
- **MEMORY.md 肥大**: 完了履歴・古い backlog が全文常駐していないか → `/weekly-inventory` で圧縮 or 非常駐ファイルへ退避。
- **重複**: 同じ規約が CLAUDE.md・rules・skill に多重掲載されていないか（単一ソース化候補）。

## Step 3: 実 cap 消費の計測プロトコル（tiering 判断の前提）

cap / model の重みは非公開なので、**実測でキャリブレートする**。

1. **セッション使用率**: `/context` で現在の占有を確認（70% 超で新規大探索を避ける＝`context-management.md`）。
2. **workflow / subagent の消費**: ワークフロー完了通知の `subagent_tokens` を記録。fan-out 1 回の実コストを掴む。
3. **tiering 効果の A/B**: 同一タスク（同一 PR の `/review` 等）を **(A) 上位モデル単独 / (B) tiering** で実行し、`subagent_tokens` の差と**見落とし findings の差**を比較。トークン削減と精度劣化を同時に測ってから tiering の採否・境界を決める（ADR-0023 決定 3）。

## Step 4: レポートと是正提案

```
=== /token-audit 結果 ===
常駐合計: X 文字（≈ Y トークン）  内訳上位: MEMORY.md / rules / CLAUDE.md ...
肥大（200行超）: N 件
path-scope 候補: ...
重複候補: ...
─────────────────
是正提案（read-only・実行はユーザー判断）:
- （最も効く削減: 例 MEMORY.md 退避 / 重い rule の path-scope）
- 実 cap 計測の次アクション（A/B 測定の対象）
```

## Return Contract

### 返すもの
- Step 4 のレポート（常駐合計・内訳上位・肥大/path-scope/重複の件数・是正提案）

### 返さないもの
- 各ファイルの全文・計測スクリプトの生出力
- 推測値を確定値として述べること（必ず確度を添える）

## Gotchas

- 推定トークンは概算。**意思決定は相対比（どこが大きいか）で行い、絶対値を断定しない**。
- path-scoped rule は常駐外なので合計から除外する（除外漏れは過大計上）。
- auto-memory のパスは slug 依存（`pwd` の `/`→`-`）。worktree や symlink 構成では実体を確認する。
- これは**検知層**であり、削減の実行（compact / 退避 / path-scope 付与）はユーザー承認のうえ別途行う。
