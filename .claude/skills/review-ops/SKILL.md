---
name: review-ops
description: "[DEPRECATED→/review] 次リリースで撤去。運用・耐障害性レビューは /review（REVIEW.md 規範 + 公式 /code-review）に統合。"
user-invocable: true
allowed-tools: "Read"
---

# ⚠️ /review-ops は非推奨（deprecated）

このスキルは **`/review` アダプタに統合**されました（ADR-0027・WS2）。**次のリリースで撤去**されます。

- **今すぐの代替**: `/review` を実行する。障害モード・可観測性・ロールバック・エラー握りつぶしの観点は **REVIEW.md §1a/§1d と fitness（`review-fitness.sh` の空 catch 検出）**、PII は `pre-commit` hook でカバーする。
- **移行ガイド**: `docs/migrations/review-6to1-adapter.md`
- **なぜ**: 機構は公式 `/code-review` に委ね、ccs は PJ 規範の注入と最終ゲートだけを持つ（二重投資の解消・モデル tier 非依存化）。

このまま続ける場合は **`/review` を実行**してください。
