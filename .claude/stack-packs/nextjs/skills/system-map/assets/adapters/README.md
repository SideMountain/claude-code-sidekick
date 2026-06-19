# system-map adapters（Next.js）

硬い層（決定的・無 LLM）のパーサ群。コードから素材を冪等に抽出し `data/*.json` に出す。軟層（サブエージェント）はその素材を意味付けするだけ。

## 同梱（全て自己検証済 = `verify-adapters.js`）

| adapter | 入力 | 出力 | 役割 |
|---|---|---|---|
| `extract-schema.nextjs.js` | `prisma/schema.prisma` + app/lib grep | `db-schema.json`（列・型・PK/FK・relations・`accessedFrom` の 1:N） | テーブル視点 |
| `extract-indexes.nextjs.js` | `prisma/schema.prisma` | `db-indexes.json`（PK/FK/UNIQUE/INDEX） | 索引視点 |
| `extract-routes.nextjs.js` | `app/**` page.tsx・api route.ts・actions.ts | `<domain>.json`（screen + api、`kind`★S4 / `trigger` / `validation` / `dbTablesRead-Write` / `calledByScreens`） | 画面・API・mutation 面 |
| `extract-authz.nextjs.js` | app/lib + `middleware.ts` + `prisma/schema.prisma` | `permissions.json`（roles / endpointAuth / spaGuards） | 入口ゲート（S5） |
| `extract-links.nextjs.js` | `app/**` の `Link`/`router.push`/`redirect` | `flow-structure.json`（screens + edges） | 画面遷移 |

```bash
# 例（対象 PJ ルートを <root>、出力を data/ とする）
node extract-schema.nextjs.js  <root> data/db-schema.json
node extract-indexes.nextjs.js <root>/prisma/schema.prisma data/db-indexes.json
node extract-routes.nextjs.js  <root> data            # <domain>.json を複数出力
node extract-authz.nextjs.js   <root> data/permissions.json
node extract-links.nextjs.js   <root> data/flow-structure.json
node verify-adapters.js                               # golden slice で全 adapter を co-validate（PASS 必須）
```

`extract-indexes`/`extract-schema` は単一 `schema.prisma` 前提（複数 datasource / multiSchema 未対応）。

> **正準 enumerator は単一定義（DRY・正準カウント凍結）**: route / screen / server-action / cron / mutation 面の母集合は `../../../../fitness-functions/lib/route-enumerator.js` が**唯一の正準定義**。`extract-routes`/`extract-authz`/`extract-links` は数え方を再実装せず、このモジュールを `require` する（route 数は数え方で 87/88/92/93/112 と揺れる。母集合を二重定義しない）。fitness-functions と system-map が同じカウントを見ることで「地図」と「検知層」が一致する。

> **硬層は骨格、軟層は意味付け（overlay）**: adapter は merge.js が既に食う既存形（`<domain>.json` / `permissions.json` / `flow-*.json` / `db-*.json`）を**決定的に**吐く。軟層（ドメイン別サブエージェント）はその骨格を**同名ファイルで enrich**（`purpose` / `summary` / `gotchas` / 画面 `kind` の意味 / webhook の `idempotency` 判定 / object-level 認可）。骨格だけでも地図は完成する＝**LLM ゼロで地図が描ける**。

## SOFT 残差（軟層に委ねる / 決定的には出せない）

| 残差 | 担当 | 理由 |
|---|---|---|
| `purpose` / `summary` / `gotchas` / `notes` | 軟層 | 意味付け（静的解析で出ない） |
| 画面 `kind`（list/form/detail/…）・`module` の意味 | 軟層 | UI 意図の分類（硬層は `module` に domain を構造 proxy として与える） |
| webhook/cron の `idempotency` 判定 | 軟層 | event-id dedup か否かは DAL の意味解釈が要る（adapter は `uncertainties` に残す） |
| object-level 認可（所有/テナント検証 S6） | 軟層 | DAL の where スコープの意味解釈（adapter は `uncertainties` に残す） |
| 動的遷移（テンプレートリテラル `href`） | 軟層 | 実行時計算（adapter は `uncertainties` に flag） |
| route の `dbTables`（DAL 2 ホップ以上の間接） | 軟層 | adapter は **1 ホップ**（api → 直接呼ぶ DAL fn → `prisma.<model>`）まで解決。多段委譲は `dbTablesWrite 未解決` を `uncertainties` に残す |

> 各 adapter は **golden path（`ARCHITECTURE.md`）への準拠を前提に決定性が上がる**。準拠しない PJ では素材が欠け、軟層の推測（`uncertainties`）が増える。これは「規約を守らせるほど地図が硬くなる」という pack の中心思想（descriptive→prescriptive）の現れ。

> **モジュール構成のメモ**: route / mutation 面は **1 つの `extract-routes`** に統合した（`api.kind`/`trigger` は api 上のフィールドであり、route と mutation を別ファイルに割ると同じ `<domain>.json` への二重書き込みになるため）。当初ロードマップの `extract-mutations` は `extract-routes` に内包。

## 既知の限界（advanced 機能・敵対検証で確認済の SOFT 残差）

golden path では稀だが、下流で使われた場合に硬層が取りこぼす（軟層 or 手動で補う）ケース。`adapters/verify-adapters.js` に主要な再発防止 fixture を同梱。

- **intercepting routes `(.)photo`/`(..)`/`(...)`**: URL マーカーが segment に残る（id/route が `feed_(.)photo` になる）。正準 enumerator の `urlSegments` が `(x)`（両端括弧）のみ除去するため。稀な advanced 機能。
- **raw SQL（`$queryRaw`/`$executeRaw`）の table**: model 名が SQL 文字列内なので `prisma.<model>.<op>` 形でなく `dbTables` に出ない（`ARCHITECTURE.md` S2 で raw は非推奨）。
- **implicit many-to-many（`A[]`↔`B[]`・@relation 無し）**: FK scalar が無いため `relations[]` に出ない。
- **`@@map`/`@map` の物理名**: `name` は Prisma model/field 名（`accessedFrom` の join キー）。物理テーブル名は意図的に採らない。
- **任意名の Prisma client alias（`const c2 = prisma`）**: `prisma`/`tx`/`db`/`client` のみ追跡（`ARCHITECTURE.md` は `@/lib/prisma` の `prisma` import を必須化）。

## 方針

このスキルの可視化コンセプト・HTML テンプレート・merge/build/verify はスタック非依存で再利用するが、**硬層パーサ（adapter）はスタックごとに書き直す**。本 pack は Next.js golden path 専用のアダプタだけを同梱し、特定プロダクト固有の素材は持ち込まない。
