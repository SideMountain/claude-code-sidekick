---
name: review-code
description: "[DEPRECATED→/review] 次リリースで撤去。実装品質レビューは /review（REVIEW.md 規範 + 公式 /code-review）に統合。"
user-invocable: true
allowed-tools: "Read"
---

# ⚠️ /review-code は非推奨（deprecated）

このスキルは **`/review` アダプタに統合**されました（ADR-0027・WS2）。**次のリリースで撤去**されます。

- **今すぐの代替**: `/review` を実行する（決定的 fitness → 公式 `/code-review` → REVIEW.md の PJ 規範 → min() 総合判定）。実装整合性・DB 設計・セキュリティは **公式 `/code-review` の effort（high / ultra）**、水平展開（diff 外の同種欠陥）は **REVIEW.md §1k**、HARD/ガード整合は **§1a** でカバーする。
- **移行ガイド**: `docs/migrations/review-6to1-adapter.md`
- **なぜ**: 機構は公式 `/code-review` に委ね、ccs は PJ 規範の注入と最終ゲートだけを持つ（二重投資の解消・モデル tier 非依存化）。

このまま続ける場合は **`/review` を実行**してください。
