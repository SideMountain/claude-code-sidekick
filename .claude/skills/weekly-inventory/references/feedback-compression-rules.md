# feedback 圧縮ルール

/weekly-inventory Step 3 で使用する feedback ファイルの整理基準。

## 昇格判定基準

以下の条件を満たす feedback は brain（L0/L1/L2）への昇格を検討する:

1. **3回以上**: 同趣旨の指摘が 3 件以上蓄積
2. **昇格先の判定**: 「同じ自分が別 PJ に行ってもこの判断するか?」
   - YES + 業界共通 → **L0** (`brain/thinking.md`、ccs 還流候補)
   - YES + 個人の癖 → **L1** (`~/.claude/brain/thinking.md`)
   - NO（PJ 依存）→ **L2** (`<PJ>/.claude/brain/thinking.md`)
3. **パターン化**: 個別事例ではなく、一般化できる原則に昇華できる

## 統合ルール

同趣旨の feedback が複数ある場合:

1. 最も具体的・包括的な feedback をベースにする
2. 他の feedback の事例・コンテキストを追記する
3. 統合元の feedback は削除せず、冒頭に `<!-- 統合済み: feedback_xxx.md に統合 -->` を追記
4. MEMORY.md の索引も更新する

## 圧縮しないもの

- 昇格済みでも、経緯記録として feedback ファイル自体は残す
- 異なる文脈の指摘を無理に統合しない（「似ているが別の問題」は別々に管理）

## 確認フォーマット

```
=== feedback 統合候補 ===
1. feedback_A + feedback_B → 「○○」として統合
   理由: 同趣旨。Aの方が具体的なので A をベースに B の事例を追記

=== 昇格候補 ===
1. feedback_C → L1 (`~/.claude/brain/thinking.md`) §1「○○」として昇格
   理由: 3回以上の指摘。複数 PJ で同じ判断をしている個人の癖
2. feedback_D → L0 (`brain/thinking.md`) §1「○○」として昇格、ccs 還流候補
   理由: 業界共通の判断軸。誰でも頷ける
```