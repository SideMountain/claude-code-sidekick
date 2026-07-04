# 公式 bundled スキルとの使い分け

`/review` は ccs 統合アダプタ（決定的 fitness + REVIEW.md 規範 + min() 総合判定）。公式 bundled の単機能スキルは置き換えではなく**補完的に**重ねる。

| 公式スキル | 役割 | `/review` との関係 |
|---|---|---|
| `/code-review` | diff の correctness バグ + reuse/simplify 検出（low〜ultra の effort、cloud 隔離も可） | `/review` の**機構そのもの**。Step 3 で呼ぶ。REVIEW.md が観点として注入される |
| `/simplify` | 変更コードの reuse / 簡潔化 / 効率の cleanup（品質のみ、バグは探さない） | `/code-review` 指摘後の整形に。バグ検出は `/code-review` 側 |
| `/verify` | アプリを実際に動かして挙動を確認（テストでなく実挙動） | `/review`（静的）の後の動的確認。Step 4 の提案先 |
| `/security-review` | セキュリティ専用の深掘りパス | `/code-review` が認可・信頼境界・入力検証の疑いを出したら委譲 |

**原則**: PR 前ゲートは `/review`（アダプタ）を主とし、公式 bundled は「特定観点を深掘りするスポット」として重ねる。**新スキルは作らず、公式を呼び分ける**（ADR-0018 の最小ループ — 能動面を増やさず配管で吸収）。
