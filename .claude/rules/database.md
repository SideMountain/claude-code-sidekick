# Database

## DB接続先の確認ルール

**DB に対する全ての操作（SELECT含む）の前に確認する:**

```bash
grep "^DATABASE_URL" .env
```

`STG_DB_PATTERN` / `PRD_DB_PATTERN` が設定されている場合:

| 接続先 | SELECT | INSERT/UPDATE/DELETE | マイグレーション |
|-------|--------|---------------------|----------------|
| STG DB | 確認不要 | ユーザー確認 | ユーザー確認 |
| 本番DB | ユーザー確認 | 手順提示→再承認 | 手順提示→再承認 |

**確認を省略してよいケースは存在しない。**

## .env の接続先ルール

- 全環境の `.env` の `DATABASE_URL` は常に**STG DB固定**。書き換え禁止
- PRD DB への操作はコマンド単位で環境変数を渡す:
  ```bash
  DATABASE_URL="prd接続文字列" node scripts/xxx.js
  ```

## ORM_TYPE=prisma の場合

- `prisma db push` 禁止。必ず `prisma migrate dev --name <説明>` を使用
- マイグレーション名: 英語スネークケース
- 生SQL（`$queryRaw` / `$executeRaw`）は原則禁止