# レビュースコア定量化ガイド（min() 総合判定）

`/review` アダプタの Step 5 が使う最終ゲート。**REVIEW.md §3 と同一の min() ルール**を指す（両者は単一の判定を共有する。数値の乖離を作らない）。

## スコア体系

各 finding を severity で分類し、検出源ごとに「最悪 severity」をスコアにする。

| severity | スコア | 意味 | アクション |
|---|---|---|---|
| BLOCKER | 1 | データ喪失・本番影響・ガード弱体化・HARD 違反・ADR 矛盾・機械検査 fail | 修正必須。PR 作成不可 |
| WARN | 2 | 破壊的変更の手順不備・テスト欠落・a11y 欠落・PJ 教訓違反 | 今回 or 次回で対応推奨 |
| INFO | 3 | 改善提案・スタイル・将来リスク | 任意 |
| （指摘なし） | 3 | — | そのまま進行 |

## 検出源（旧 5 観点はアダプタ化で統合）

| 検出源 | スコア基準 |
|---|---|
| fitness（`review-fitness.sh` / `run-fitness.js`） | `run-fitness` の error=BLOCKER。`review-fitness` の検出=WARN 入力 |
| 公式 `/code-review` | 返った findings の severity をそのまま採用（REVIEW.md §2 の定義で確定） |
| REVIEW.md PJ 規範（§1） | HARD 違反・ガード弱体化・ADR 矛盾=BLOCKER。破壊的手順不備・教訓違反=WARN |

## 総合判定の算出

```
総合スコア = min(全検出源のスコア) = 存在する最悪 severity

判定:
  3: PR作成可（指摘なし / INFO のみ）
  2: PR作成可（WARN のみ。対応はユーザー判断）
  1: ブロッカーあり。修正必須（PR 作成不可）
```

**平均・多数決・「全体としては良いので」による格上げは禁止。BLOCKER が 1 件でもあれば総合 1。**

## STG 自動マージの条件（将来）

以下を全て満たす場合、STG マージを自動化できる:

```
条件:
  1. /review 総合スコア >= 2
  2. テスト全 PASS（TEST_COMMAND 実行結果）
  3. 型チェック PASS（TYPECHECK_COMMAND 実行結果）
  4. セキュリティ深掘り（/security-review）が未指摘
  5. PR の変更行数が閾値以内（デフォルト: 500行）
```

1 つでも条件を満たさない場合は手動マージ。
