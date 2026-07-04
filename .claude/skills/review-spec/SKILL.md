---
name: review-spec
description: "[DEPRECATED→/review] 次リリースで撤去。仕様品質レビューは /review（REVIEW.md 規範 + 公式 /code-review）に統合。"
user-invocable: true
allowed-tools: "Read"
---

# ⚠️ /review-spec は非推奨（deprecated）

このスキルは **`/review` アダプタに統合**されました（ADR-0027・WS2）。**次のリリースで撤去**されます。

- **今すぐの代替**: `/review` を実行する。API 契約・仕様書乖離・破壊的変更の観点は **REVIEW.md §1b/§1c（DB + API 契約の両方）と fitness（`review-fitness.sh` の破壊的キーワード検出）**でカバーする。
- **移行ガイド**: `docs/migrations/review-6to1-adapter.md`
- **なぜ**: 機構は公式 `/code-review` に委ね、ccs は PJ 規範の注入と最終ゲートだけを持つ（二重投資の解消・モデル tier 非依存化）。

このまま続ける場合は **`/review` を実行**してください。
