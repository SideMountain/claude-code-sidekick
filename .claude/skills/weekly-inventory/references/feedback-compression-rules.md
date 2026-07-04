# feedback 圧縮ルール（/weekly-inventory Step 3）

**同趣旨判定（R5）・昇格判定（R6・致命クラス閉集合）・還流 3 分類（R7）・few-shot・統合ルールは `.claude/docs/knowledge-reflux.md`（単一ソース）を参照する。** このファイルは weekly-inventory Step 3 の確認フォーマットだけを持つ。

判定手順:

1. **同趣旨クラスタリング** — feedback ペアを doc の R5（2/3 YES）で判定し、件数をカウント（同趣旨 3 件で昇格候補）。
2. **統合** — doc「統合ルール」に従う（最具体をベースに事例を追記・統合元は削除せず注記）。
3. **昇格** — doc の R6（3/4 YES・致命クラスは N=1）で判定し、R7 で昇格先を決める。

## 確認フォーマット

```
=== feedback 統合候補 ===
1. feedback_A + feedback_B → 「○○」として統合
   理由: R5 で同趣旨（2/3 YES）。Aの方が具体的なので A をベースに B の事例を追記

=== 昇格候補 ===
1. feedback_C → 個人 brain (`~/.claude/brain/thinking.md`) §1「○○」として昇格
   理由: R6 3/4 YES + 3 件蓄積。複数 PJ で同じ判断をしている横断軸（R7=個人 brain 昇格）
2. feedback_D → OSS 還流候補（sidekick `brain/thinking.md` §1「○○」へ手動 PR）
   理由: R6 満たす。業界の誰が読んでも行動が変わる（R7=OSS 還流候補）
```
