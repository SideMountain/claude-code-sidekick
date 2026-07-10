# ARCHITECTURE.md — Next.js Golden Path（背骨docs / Spine）

> このファイルは ccs の **Next.js stack pack** が配布する**規定アーキテクチャ（prescriptive）**。
> 下流PJ はこの規約に従って実装する。目的は2つ:
> **(a) 一貫した良いアーキテクチャ** / **(b) `system-map` のパーサが決定的になる**（アーキが既知 → 静的に「地図が自分で描かれる」）。
>
> **位置づけの正は同 dir `README.md`**（opt-in / ccs core との関係）。ここでの前提: 規約を当てる "方法"（アーキを規定 → 決定性 → 強制で守らせる）は stack 非依存で、Next.js はその第一インスタンス（ADR-0021）。

## 対象スタック（baseline）

Next.js **App Router**（15 / 16）+ React 19 + **Prisma** + 認証ライブラリ（next-auth / Auth.js v5 / Better Auth / Clerk 等・非依存）+ **zod**（Standard Schema 準拠バリデータ・既定 Zod）+ vitest + playwright。

- **Rendering baseline = 従来モデル**（`export const dynamic` / `revalidate`）。**Cache Components（`use cache` / `cacheLife`）は opt-in な将来パス**（下流が Next 16+ で採用したら移行・ロックアウトしない）。
- **`middleware` / `proxy`**: Next 16 で `middleware` は `proxy` に改称（deprecated だが併存・edge fallback で `middleware` 維持）。規約・ツールは**両名を認識**すること。

## 読み方

| 区分 | 意味 |
|---|---|
| **Tier-1 STRUCTURAL** | parser 決定性に **load-bearing**（soft→hard を動かす）。厳格な **MUST** |
| **Tier-2 HYGIENE** | 一貫性 / DX。守るが新しい硬い層は生まない。多くは **SHOULD** |
| **① 公式** | Next.js 公式が推奨するデフォルト。論争少 |
| **② 主流** | 業界で広く支持されるが「公式の既定」より一歩強い。本 pack では決定性のため MUST/SHOULD に**格上げ**（出自を明記） |
| **③ ccs 独自** | Next 標準には無い。`system-map` の決定性のための規約 |

> **格上げの誠実性**: ②③ を MUST に格上げする箇所は必ず「公式は recommend 止まり / 標準に無い」+「ccs 決定性のため」を併記する。過剰規約（目的原則「組み立て不要」違反）を自己抑制するため、load-bearing でない規約は SHOULD に留める。
>
> **逸脱（escape hatch）**: golden path は既定であって、拘束が目的ではない。逸脱する場合は**理由をコードコメント or PR に明記**する（fitness 関数が検出する）。黙って外さない。

---

# Tier-1 STRUCTURAL（MUST・決定性 load-bearing）

## S1. 依存方向は単方向・`@/*` alias・barrel ゼロ

- **判定**: MUST（依存方向=②→決定性 / `@/*`=① / barrel ゼロ=②→③）
- **規約**:
  - `lib/` と `components/` は `@/app` を import してはならない。循環依存ゼロ。
  - 全 import は `@/*` alias を使う。
  - **barrel（`index.ts` による re-export 集約）を作らない**。例外: ライブラリ的な public entry point は除外してよい（but-clause）。
- **出自**: 単方向依存は普遍原則。`@/*` は公式デフォルト。**barrel ゼロは Next 標準では SHOULD**（公式は禁止せず `optimizePackageImports` という緩和策を出す立場・対象は外部パッケージ限定で local barrel には効かない / Turbopack も re-export barrel の不要モジュール除去は未対応〔16.2 既知制約〕）→ ccs は parser のシンボル↔ファイル住所トレースのため MUST に格上げ。
  - 注: 決定性に効くのは **barrel ゼロ + 単方向**。`@/*` alias 自体は DX で決定性中立（① 公式）。dogfood 実測では依存方向の規約は計測 2 PJ とも**自然準拠**で、MUST 化の摩擦は小さい（既に守られているものを規約として明文化する形）。
- **検証**: `grep -rl 'from .@/app' lib components` = 0 ／ `find lib components -name index.ts`（public entry を除く）= 0 ／ `madge --circular` = 0

## S2. route handler は DB を直接触らない — DAL/service 層経由

- **判定**: MUST（②→決定性のため格上げ）
- **規約**: `app/api/**/route.ts` は HTTP メソッドを named export し、**`認証ゲート → バリデーション → service 関数呼び → レスポンス整形`** のみを担う。route から `@/lib/prisma` を import しない。DB アクセス・ビジネスロジックは `lib/services/<domain>.ts`（= **DAL**, HTTP 非依存）に置く。依存方向は **route → service の一方向**。
- **出自**: Next.js 公式 security ガイドは新規PJに **DAL を推奨**し、component/route での直アクセスを「プロトタイプ向け・データ漏洩リスク高」と劣位化。ただし**公式は recommend 止まり**（Prisma 公式は直アクセスを許容し DAL を要求しない）→ ccs は決定性のため MUST に格上げ。
- **なぜ決定性**: route に prisma import が無ければ DB 依存は service グラフで閉じ、**route の静的走査だけで「どの API がどの table を触るか」が辿れる**。
- **検証**: `grep -rl '@/lib/prisma' app/api --include=route.ts` = 0 ／ route.ts は概ね ≤80 行

## S3. データは in-page で取得しない（server-first）

- **判定**: MUST（① 公式・ただしデータ取得部分のみ）
- **規約**: `page.tsx` / コンポーネントは **`useEffect` + `fetch('/api/*')` で自分の初期データを取得しない**。初期データは server boundary（Server Component の fetch / DAL）から **props で渡す**。
  - **`'use client'` 自体は禁止しない**（interactive な page は client のままでよい・leaf には props でデータを渡す）。「全 page を Server Component に」は要求しない。
- **出自**: Next.js 公式「Fetch data in Server Components directly from its source, not via Route Handlers」。公式の client-fetch 選択肢に `useEffect` は無い（`use` API / SWR / React Query のみ）。
- **なぜ決定性**: データ binding が runtime の `useEffect` 文字列でなく **import グラフ**に乗り、screen→data が静的に辿れる。
- **検証**: `page.tsx` 内に `useEffect` と `fetch(` の同時出現 = 0

## S4. mutation 面 = Server Action（内部）+ route handler（外部）— 本質は「列挙可能な単一機構」

- **判定**: MUST（① 分担 / ③ actions.ts 集約・列挙性は決定性のため）
- **本質（手段より上位）**: この規約が守りたいのは「**全 mutation 入口が grep で網羅列挙できる単一機構で宣言される**」こと。Server Action / route handler はその手段であって、load-bearing なのは**列挙可能性**。手段（Server Action か route handler か）はスタック流儀で変わってよいが、列挙可能性は変えない。
- **規約**:
  - 内部 mutation は **Server Action**、外部公開 HTTP は **route handler** に分ける。Server Action は **`actions.ts` にファイル先頭 `'use server'` + named export** で集約する（route handler に全 mutation を押し込まない）。
  - **コンポーネント内の inline `'use server'` クロージャは禁止**（JSX 内クロージャは grep 列挙が原理的に不能になり、本質＝列挙可能性を壊す）。Server Action は必ず module-level（`actions.ts`）。
  - **mutation の trigger を分類する**（system-map が taxonomy 化）: ① page 到達（screen→action/route）/ ② scheduler（cron）/ ③ provider-callback（webhook）/ ④ internal。**②③ は page から辿れないが blast-radius が大きい**（課金照合・一括処理等）。route handler として**必ず mutation 列挙の対象に含める**（「page から辿れる入口だけ」を mutation 面と見なさない）。
- **出自**: 公式「Next.js handles mutations with Server Actions」（= 内部 mutation のベストプラクティス）。route handler は外部向けに retain。`actions.ts` 集約 + inline 禁止 + trigger 列挙は ③ ccs 独自（parser が mutation 面を**手段非依存に**静的列挙できるようにするため）。
- **検証**: `'use server'` を持つファイルは `actions.ts`（または `**/actions.ts`）に限る ／ route/component 内の散在・inline `'use server'` = 0 ／ cron（`vercel.json` の `crons` 等）と webhook route も mutation 列挙に含む

## S5. 認証コア — 単一 helper・データ近接 verify・middleware を唯一境界にしない

- **判定**: MUST（① 公式）
- **規約**:
  - 認証は **単一の helper**（例 `requireSession()` / `requireRole()`）経由で行い、`getServerSession` 等のセッション/role チェックを route や page に **inline 複製しない**。
  - 認可チェックは **データに最も近い場所（DAL）で**行う。`middleware`/`proxy` を**唯一の防衛線にしない**（必ず DAL/route でも再検証）。
- **出自**: 公式 auth ガイド「verify close to your data source」「DAL で centralize」/ CVE-2025-29927（middleware bypass）postmortem「do not recommend Middleware to be the sole method of protecting routes」。
- **shape（②③・SHOULD）**: role/scope を Prisma enum で比較（文字列リテラル禁止）・**allowlist のみ**（default-deny）・`ctx` に `companyId` 等テナント境界を同梱・discriminated-union 返り（`{ok,ctx}|{ok,response}`）。※ shape は ccs 独自の流儀（公式例は throw/redirect）。parser に MUST で要るのは「**単一 named helper 経由**」だけ。
- **検証**: `getServerSession`（等）が auth helper の外に出現 = 違反 ／ `role === '` `role !== '` 文字列リテラル = 違反

## S6. 認可は object-level で DAL に強制（直URL / IDOR を構造で塞ぐ）

- **判定**: MUST（① 公式）
- **規約**: 「gate の有無 + 要求 role」（S5）に加え、**リソースアクセス時に owner / tenant / 対象 ID を verify** する。DAL の各データ取得関数が「**この呼び出し主体がこの行を見てよいか**」を強制する（route gate だけに頼らない）。URL を直接叩いても・ID を推測しても、認可されないリソースは返らない。
- **出自**: 公式 security「The majority of security checks should be performed as close as possible to your data source」「re-read access control」。OWASP の Broken Object Level Authorization（IDOR）対策。
- **なぜ決定性 + 安全**: 認可がデータ近接の DAL に集約されると、parser が「どの resource にどの認可が掛かるか」を service 層で追える（route 散在だと soft）。同時に「直URL NG」が**構造で**成立する。
- **検証**: DAL のリソース取得関数が tenant/owner スコープ（例 `where: { companyId, id }`）を持つ ／ route gate のみで DAL がスコープを欠く取得 = 違反
- **残余**: 行レベルの**業務ルール認可**（「差戻し中のみ編集可」等）は logic として残り、完全 hard 化はしない（SOFT・後述）。

## S7. validation — schema 単一ソース + server 再検証

- **判定**: MUST（① schema 単一ソース + server 再検証）/ SHOULD（③ 配置・ライブラリ固定）
- **規約**:
  - request contract は **Standard Schema 準拠バリデータ（既定 Zod）**の named schema を `lib/validations/<domain>.ts` から export（schema + `z.infer` 型の両方）。route 内 `z.object` literal 定義を避ける。
  - body は `schema.safeParse(...)`（throw する `.parse()` でなく）。**client form があっても server 側で必ず再検証**（client schema を server schema の単一ソースから派生）。
- **出自**: zod は TS/Next の de-facto・Standard Schema が確立（lock-in 回避）。schema 集約・配置は ③ 決定性（route→schema が単一 import エッジ）。
- **検証**: `grep 'z.object' app/api --include=route.ts` = 0

## S8. 層間トレーサビリティ — エッジを決定化（「地図が自分で描かれる」核心）

- **判定**: MUST（②→③ 決定性のため格上げ）
- **規約**:
  - **feature colocation**: screen と それが呼ぶ server data 関数を共有 feature key 下に置く（`app/<feature>` が `lib/<feature>/queries.ts` を import）。screen→data を import エッジにする。
  - **命名ブリッジ**: service / DAL 関数は主 Prisma model を関数名 or 注釈で encode する（API→table を grep で辿れる）。
  - route path segment を feature / model 語彙に揃える。
- **出自**: 公式 Project structure は**3戦略を許容**（unopinionated）→ ccs は parser のため **Split-by-feature に固定**。命名ブリッジは ③ ccs 独自（screen↔API↔service↔table を連結グラフにする・地図の核心）。
- **なぜ決定性**: 各層を hard にしても**層間のエッジ**が soft なら「5つのリスト」であって「地図」でない。この規約がエッジを hard にする。

---

# Tier-2 HYGIENE（一貫性 / DX）

## H1. データ層

- **判定**: MUST（singleton=①）/ SHOULD（soft-delete / 命名）
- **規約**:
  - DB は **単一 Prisma シングルトン**（`@/lib/prisma` のみ・追加 `new PrismaClient` 禁止・dev のみ `globalThis` キャッシュ・**接続文字列を `console.log` しない**）。
  - 論理削除 `deletedAt: null` は **`$extends`（client extension）でクエリ境界に自動注入**（callsite 手書き禁止）。
  - **retry は `$extends` に畳まない** — operation / transaction スコープの wrapper（`withRetry`）で統一（aborted tx 内の単文 retry は正当性を壊す）。
  - ドメイン不変条件を持つ書き込み（残高・台帳・状態遷移）は `lib/<domain>.ts` に切り出し **`tx: Prisma.TransactionClient` を引数**に取り `$transaction` 内で実行。
  - マイグレーション命名 `YYYYMMDDHHMMSS_<説明>`。`prisma db push` は物理ブロック維持。
- **残余裏取り**: soft-delete の `$extends` 実装・migration 命名は Prisma 公式 docs で最終確認すること（residual・確度中）。

## H2. エラー & レスポンス

- **判定**: SHOULD（一部 ① 方向）
- **規約**:
  - catch して 5xx を返すなら **PJ 定義の単一エラー seam 経由**で報告（`Sentry.captureException` / `console.error` の直呼びを報告経路にしない）。**特別な後処理が不要なら throw して `instrumentation.ts` の `onRequestError` に委ねる（こちらが原則）**。seam の具体名は PJ が定義する（規約に含めない）。
  - レスポンスは成功 `{ data }`（必要なら `pagination`）/ 失敗 `{ error }` の単一エンベロープ。
  - **webhook / scheduler の冪等性（SHOULD）**: provider-callback（webhook）は **at-least-once 配信前提**。event-id を**永続化して replay を短絡**するか、全副作用が**証明可能に冪等**であること。`findUnique`-based の business-key upsert は DB 行は冪等でも、通知送信等の副作用は replay で二重発火しうる（event-id を log するだけでは不十分）。cron も多重起動を前提に冪等に。
- **出自**: `onRequestError` 集約は公式方向。エンベロープは公式に標準が無い（③ ccs・SHOULD）。冪等性は分散配信の普遍原則（dogfood で webhook の replay-safety gap を検出・SHOULD）。

## H3. Rendering & framework files

- **判定**: MUST（framework files / segment-config 規律）/ baseline 宣言
- **規約**:
  - **Rendering baseline = 従来モデル**（`export const dynamic` / `revalidate`）。**Cache Components は opt-in future**（採用するなら golden path 前提として宣言・`dynamic`/`revalidate` は使わない）。
  - server-render 既定・可能なら static。**blanket `force-dynamic` 禁止**（API route の `force-dynamic` は可、page の常時 `force-dynamic` は是正）。segment config は**正当化できる箇所のみ理由コメント付き**で明示（全 route 明示は禁止）。
  - routing 構造（auth 境界・sidebar 有無等）は **route group `(group)` + per-segment `layout.tsx`** で表現。`layout.tsx` が `usePathname()` + ハードコード prefix 配列で分岐するのを禁止。
  - **resilience 境界（SHOULD）**: データ取得を伴う segment は `error.tsx` + `loading.tsx` を持つ（部分的失敗・遅延を UI 境界で受ける）。動的 lookup を持つ segment は `not-found.tsx`。app は `global-error.tsx` を1つ（フレームワーク強制 convention）。`global-error.tsx` だけで個別境界ゼロは是正対象（dogfood で全 page に境界ゼロを検出）。

## H4. 構造ハイジーン

- **判定**: MUST（feature-first / server-only=①）
- **規約**: `lib/<feature>/` を一次配置・flat（root `lib/` / `components/`）は cross-cutting ユーティリティ限定。server 専用ロジックは `import 'server-only'`。tracked tree に `.backup` / `.tmp` を残さない。

---

# 決定性スコープ（実態に即した記述）

「100% hard・推測ゼロ」は**地図全体でなく以下の feature に限定**した約束。

| | 内容 |
|---|---|
| **HARD（地図が自分で描かれる）** | route 一覧 / **API→service→table の import グラフ** / **mutation 面（route handler + module-level Server Action、全 trigger = page到達 + cron + webhook）** / 入力 contract（schema が存在する箇所）/ **認可マトリクス（gate 有無 + 要求 role）** / **object-level 認可の存在**（DAL 取得関数が tenant/owner スコープ引数を持つか）/ 依存方向 |
| **SOFT（規約100%でも LLM が要る残余）** | interactive leaf の自前 fetch / 動的クエリの model 到達性 / **行レベルの業務ルール認可** / **object-level 認可の全分岐網羅性**（存在は HARD・全 data-path での完全性は data-flow 解析が要り SOFT）/ **入力検証の妥当性**（schema の有無は静的に取れるが「検証として十分か」は別）/ out-of-band な認証 realm（Basic-Auth・webhook 署名・cron secret 等） |

> **mutation 列挙の正準カウント**: route 数は「ファイル数」「method export 数」「page+API 合算」で値が変わる（dogfood で 87/88/92/93/112 と測定がぶれた）。adapter は **route enumerator を単一の正準定義に凍結**し（推奨: route.ts ファイル × 各 method export を 1 entry）、全 fitness 関数がそれを参照する。母集合が未確定のまま HARD/SOFT を配分しない。

---

# 強制（fitness functions）

各 Tier-1 MUST の **検証（grep-checkable assertion）**を **architecture fitness 関数**として実装し、CI で実行して「認知 → 強制 → 検知」の検知層を成立させる。本 pack が `fitness-functions/` に同梱する（依存ゼロの plain Node）:

```bash
node .claude/stack-packs/nextjs/fitness-functions/run-fitness.js .   # = npm run test:arch（error で exit 1）
```

vitest 統合が要れば `fitness-functions/templates/architecture.test.ts` を `__tests__/architecture/` にコピーする（1 ルール = 1 test）。**error = HARD（落とす）/ warn = SHOULD・SOFT 残差（可視化のみ）** に対応し、上の決定性スコープ表をコードでも守る。新規 PJ は `scaffold/` で最初から規約に乗せられる（scaffold 出力 ≡ fitness の conforming fixture でドリフト不能）。詳細は `fitness-functions/README.md` / `scaffold/README.md`。

> 関連: ADR-0021（stack pack 方式）/ ADR-0019（opt-in ハーネス）/ ADR-0018（目的原則）/ ADR-0020（Spine / Observability の解凍）。検証の一次出典は本 pack の `README.md` を参照。
