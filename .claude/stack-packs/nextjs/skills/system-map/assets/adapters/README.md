# system-map adapters（Next.js）

硬い層（決定的・無 LLM）のパーサ群。コードから素材を冪等に抽出し `data/*.json` に出す。軟層（サブエージェント）はその素材を意味付けするだけ。

## 同梱

| adapter | 入力 | 出力 | 状態 |
|---|---|---|---|
| `extract-indexes.nextjs.js` | `prisma/schema.prisma` | `db-indexes.json`（PK/FK/UNIQUE/INDEX） | ✅ 同梱・自己検証済 |

```bash
node extract-indexes.nextjs.js prisma/schema.prisma data/db-indexes.json
```

単一 `schema.prisma` 前提（複数 datasource / multiSchema 未対応）。`@id`/`@@id`/`@unique`/`@@unique`/`@@index`/`@relation(fields/references)` を regex 抽出する。

## ロードマップ（段階導入・北極星「組み立て不要」）

残りの硬層は **手作業でも素材は出せる**ため、スクリプト化は段階導入する（一度に全部作らない）。当面は SKILL.md の Step 1 に従い Glob/Grep で出し、頻出すればスクリプト化する。

| 予定 adapter | 役割 | 決定性 | 備考 |
|---|---|---|---|
| `extract-routes.nextjs.js` | `app/**/page.tsx`・`app/api/**/route.ts` を走査し画面・API の素材 | 硬 | 動的 segment `[id]`・ルートグループ `(group)` の解釈 |
| `extract-mutations.nextjs.js` | `"use server"` の export = Server Action / `route.ts` の export = Route Handler（`api.kind` ★S4） | 硬 | golden path S4 が効くほど正確 |
| `extract-authz.nextjs.js` | `middleware.ts` matcher + DAL の `requireRole`/所有検証 | 硬寄り | 二層認可（S5/S6）。middleware だけに依存しない前提 |
| `extract-links.nextjs.js` | `<Link href>`・`useRouter().push()` の双方向リンク → flow | 硬寄り | 対話的 leaf の動的遷移は SOFT 残差 |

> 各 adapter は **golden path（`ARCHITECTURE.md`）への準拠を前提に決定性が上がる**。準拠しない PJ では素材が欠け、軟層の推測（`uncertainties`）が増える。これは「規約を守らせるほど地図が硬くなる」という pack の中心思想（descriptive→prescriptive）の現れ。

## 方針

このスキルの可視化コンセプト・HTML テンプレート・merge/build/verify はスタック非依存で再利用するが、**硬層パーサ（adapter）はスタックごとに書き直す**。本 pack は Next.js golden path 専用のアダプタだけを同梱し、特定プロダクト固有の素材は持ち込まない。
