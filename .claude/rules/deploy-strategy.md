---
paths:
  - "prisma/**"
  - "drizzle/**"
  - "**/migrations/**"
  - "scripts/**"
---

# Deploy Strategy

> path-scoped: マイグレーション / デプロイ / backfill スクリプトに触れる変更でのみロードされる（常駐ダイエット）。DB 無し PJ では非ロード（dead weight 解消）。

## マイグレーションとデプロイの順序

**Expand-Contract パターン**で安全にリリースする。

| 変更の種類 | デプロイ手順 |
|-----------|------------|
| 追加系（非破壊的） | 先にマイグレーション → 後にデプロイ |
| 削除/変更系（破壊的） | 2段階リリース（Expand-Contract） |

**破壊的変更**: DROP COLUMN/TABLE、ALTER TYPE、RENAME、NOT NULL追加
**非破壊的変更**: ADD COLUMN、ADD VALUE、CREATE TABLE/INDEX

## バックフィルスクリプトのルール

- 必ず `scripts/` にコミットする（使い捨て禁止）
- `--dry-run` オプションを実装する
- 本番リリース完了後も削除しない