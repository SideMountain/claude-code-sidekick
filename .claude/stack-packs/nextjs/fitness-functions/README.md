# fitness-functions — golden path の検知層

`ARCHITECTURE.md` の各 MUST を **grep-checkable assertion** に落とした architecture fitness 関数群。
「認知（ARCHITECTURE.md）→ 強制（scaffold で最初から規約に乗せる）→ **検知（ここ）**」の検知層。

依存ゼロ（Node 標準のみ・正規表現の静的走査）。実行も型解決もしない。下流PJ にそのまま載る。

## 実行

```bash
# 主: 単一 Node プロセス（WSL の vitest worker hang を回避）。error があれば exit 1。
node .claude/stack-packs/nextjs/fitness-functions/run-fitness.js .
#   = package.json の "test:arch"

# 代替: vitest 統合（1 ルール = 1 test）。templates/architecture.test.ts を
#       下流の __tests__/architecture/ にコピーする。
```

## severity モデル（決定性スコープの正直な約束）

| severity | 意味 | CI |
|---|---|---|
| **error** | HARD（決定性 load-bearing）。違反は構造的に黒 | exit 1（落とす） |
| **warn** | SHOULD / SOFT 残差（存在=HARD だが網羅=SOFT 等） | 可視化のみ（落とさない） |

`ARCHITECTURE.md` の決定性スコープ表に対応する。**「100% hard」は地図全体でなく一部 feature に限定**という約束をコードでも守る — 機械的に hard 化できない残余（行レベル業務認可・object-level の全分岐網羅・検証の妥当性）は warn に留め、error で過剰に落とさない。

## ルール対応表

| rule | tier | assertion（要旨） | 判定 |
|---|---|---|---|
| **S1** | T1 | lib/components が `@/app` を import / barrel(re-export index) | error（循環依存は下記★） |
| **S2** | T1 | `app/api/**/route.ts` が `@/lib/prisma` を import | error（行数超過は warn） |
| **S3** | T1 | `page` 内に `useEffect` + `fetch` 同時 | error |
| **S4** | T1 | module-level `'use server'` が `actions.ts` 外 / inline `'use server'` クロージャ | error |
| **S5** | T1 | 生セッション読み取りが auth helper 外 / role を文字列リテラル比較 | error |
| **S6** | T1 | DAL 単一エンティティ read/write（find/update/delete by id）が tenant/owner スコープを欠く | **warn**（存在=HARD・網羅=SOFT） |
| **S7** | T1 | `app/api/**/route.ts` 内に `z.object` literal | error |
| **H1** | T2 | `new PrismaClient` が `lib/prisma.ts` 外（error）/ `process.env.DATABASE_URL` の**値**を console 出力（error）/ DATABASE_URL への言及 console＝ラベル・存在チェック等（warn・値漏洩でないか確認） | error / warn |
| **H3** | T2 | page の常時 `force-dynamic` / data 取得 segment に error 境界なし / layout の `usePathname` 分岐 | warn |
| **H4** | T2 | `.backup`/`.tmp` が tree に残る / prisma 利用 lib に `server-only` なし | error（.backup） / warn |

> S8（層間トレーサビリティ）は命名ブリッジ等が主で **SOFT 寄り**のため、現状 fitness では強制せず system-map の硬層 adapter が利用する（`ARCHITECTURE.md` 決定性スコープ表参照）。
>
> ★ **S1 の `madge --circular = 0`（循環依存）は本 fitness では非対象（out-of-scope）**: 循環検出は実際の module リゾルバが要り、zero-dep の regex 設計と両立しない。CI に `madge --circular` を併設して補う（`ARCHITECTURE.md` S1 の検証行参照）。S1 の依存方向（`@/app` import）と barrel は本 fitness が hard で見る。

## 正準カウント（単一定義の原則）

route 数は数え方で揺れる（dogfood で 87/88/92/93/112 と測定がぶれた）。`lib/route-enumerator.js` が**唯一の正準定義**:

- route entry = `(route.ts, HTTP method export)` の組
- screen = `page.tsx` 1 つ / server action = `actions.ts` の module-level named export 1 つ / cron = `vercel.json` crons[]
- mutation 面 = mutating route + server action + cron + webhook を **trigger taxonomy** 付きで列挙

fitness と（後続の）system-map route adapter は**必ずここを import**する。母集合を二重定義しない。

## escape hatch（黙って外さない）

golden path は既定であって牢獄ではない。逸脱は**コメントで明示**する（fitness が認識して抑止）:

| マーカー | 対象 | 用途 |
|---|---|---|
| `// barrel-ok` | S1 | ライブラリ的 public entry の re-export index を許可 |
| `// authz-ok` | S6 | 冪等性キー / 署名 gated 等、正当な非テナント取得を許可 |

## カスタマイズ

- **S5 の生セッショントークン**: 各 PJ の auth ライブラリの reader を `checks.js` の `S5.rawSessionTokens` に追記する。既定は `getServerSession`/`unstable_getServerSession`/`currentUser`/`getSession`。**Auth.js v5 の `auth()` は語が一般的すぎて誤検知しうるため既定に含めない** — Auth.js v5 を使う PJ は `'auth'` を追記する。
- **S6 のスコープキー**: テナント境界列が `companyId` 以外なら `S6.scopeKeys` に追記する。

## 自己検証

```bash
node verify.js   # conforming(=scaffold/template) が error 0 / 各 violation fixture で該当ルール発火
```

`scaffold/template` は fitness の **conforming fixture そのもの**（scaffold 出力 ≡ fixture）。
これにより「scaffold は規約を満たすコードを生む」「fitness は規約準拠を正しく通す」を同時に保証する。
`fixtures/violations/<rule>/` は各ルールが**本当に違反を捕まえる**こと（false-negative なし）を保証する。
