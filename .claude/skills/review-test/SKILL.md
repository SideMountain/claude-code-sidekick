---
name: review-test
description: "[DEPRECATED→/review] 次リリースで撤去。テスト品質レビューは /review（REVIEW.md 規範 + 公式 /code-review）に統合。"
user-invocable: true
allowed-tools: "Read"
---

# ⚠️ /review-test は非推奨（deprecated）

このスキルは **`/review` アダプタに統合**されました（ADR-0027・WS2）。**次のリリースで撤去**されます。

- **今すぐの代替**: `/review` を実行する。テスト網羅性は **REVIEW.md §2**（変更されたランタイム表面に対応テストなし = WARN）、モック忠実性（型・構造が実 DB/API と一致）は **§1j** でカバーする。
- **移行ガイド**: `docs/migrations/review-6to1-adapter.md`
- **なぜ**: 機構は公式 `/code-review` に委ね、ccs は PJ 規範の注入と最終ゲートだけを持つ（二重投資の解消・モデル tier 非依存化）。

このまま続ける場合は **`/review` を実行**してください。
