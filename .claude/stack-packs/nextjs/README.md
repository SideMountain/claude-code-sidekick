# Next.js Stack Pack

ccs の **opt-in な参照 stack pack**。Next.js（App Router）+ Prisma + 認証 + zod の PJ に、**規定アーキテクチャ（golden path）+ システム可視化 + 強制**を一式で提供する。

## これは何で、何でないか

- **opt-in**: Next.js を使わない PJ は何も受け取らない（無コスト）。`/setup` で「Next.js stack pack を使う」と申告した PJ にのみ配置される。
- **参照 pack ≠ ccs core**: ccs の core（hooks / brain / 北極星 / skills / 安全層）は **stack 非依存のまま一次**。本 pack はその上に載る opt-in レイヤー。**ccs は Next 専用にはならない**（ADR-0021）。
- **方法は stack 非依存・Next.js は第一インスタンス**: 「**アーキを規定する → 地図が自分で描ける → 強制で守らせる**」という方法自体は stack に依存しない。Spring pack でも Python pack でも同じ方法で別ルールを書くだけ。Next.js はその最初の参照実装。

## なぜ規定するのか（descriptive → prescriptive）

任意のコードベースを逆解析して可視化する（descriptive）と、PJ ごとに構造が違うので推測（LLM・軟らかい層）に落ちる。「汎用」と「決定的」が両立しない。

**規約を固定する（prescriptive）と、パーサは "汎用" と "決定的" を同時に満たす** — どの PJ でも同じ階層・同じ規約で書くと、パーサは*その規約*を読むだけで済み、対象が変わっても 100% 硬い層で「地図が自分で描かれる」。`ARCHITECTURE.md` はその契約。

## 中身（roadmap）

| 構成物 | 役割 | 状態 |
|---|---|---|
| **`ARCHITECTURE.md`** | golden path（規定アーキ・Tier-1/2・①②③・MUST/SHOULD・検証付き） | ✅ 本 PR |
| `skills/system-map/` | コードベースを単一 HTML で可視化（screen↔API↔DB↔権限↔遷移） | ⏳ Next.js 版へ rebuild + 固有名詞 scrub の上、本 pack 配下へ（別作業。現状は Spring/Vue 版＝固有名詞を含むため未取込） |
| `fitness-functions/` | `ARCHITECTURE.md` の各 MUST を CI で検知（`__tests__/architecture/*.test.ts` テンプレ） | ⏳ 後続 phase（認知→強制→検知 の検知層） |
| `scaffold/` | 新規 PJ を規約へ scaffold | ⏳ 後続 phase |
| `/setup` 連携 | UI opt-in と同様に pack を opt-in 配置 | ⏳ 後続 phase |

> **段階導入の規律**: 一度に全部作らない（北極星「組み立て不要」/ 70%で動く）。`ARCHITECTURE.md`（契約）→ system-map（決定的に描く）→ fitness 関数（守らせる）→ scaffold（最初から規約に乗せる）の順。

## golden path の出自（裏取り済み・2026 時点）

`ARCHITECTURE.md` の各規約は現行公式（Next.js 16.2.9 docs 群・2026 更新）で裏取り済み。MUST に格上げした ②③ は本文で出自を明記している。主要出典:

- Next.js Data Security（DAL 推奨・component-level は prototype 限定）: https://nextjs.org/docs/app/guides/data-security
- Next.js Authentication（DAL で authz 集約・データ近接 verify）: https://nextjs.org/docs/app/guides/authentication
- Server Components & Actions security: https://nextjs.org/blog/security-nextjs-server-components-actions
- Middleware bypass postmortem（CVE-2025-29927・middleware を唯一境界にしない）: https://vercel.com/blog/postmortem-on-next-js-middleware-bypass
- Fetching Data（server-first・Route Handler 経由にしない）: https://nextjs.org/docs/app/getting-started/fetching-data
- Backend for Frontend（mutation=Server Action / route handler=外部）: https://nextjs.org/docs/app/guides/backend-for-frontend
- Project structure（unopinionated・3戦略）: https://nextjs.org/docs/app/getting-started/project-structure
- optimizePackageImports（barrel 緩和は外部のみ）: https://nextjs.org/docs/app/api-reference/config/next-config-js/optimizePackageImports
- Standard Schema（Zod lock-in 回避）: https://standardschema.dev/
- version 16 upgrade（middleware→proxy / Cache Components）: https://nextjs.org/docs/app/guides/upgrading/version-16

## 関連 ADR

- **ADR-0021**: Next.js stack pack の新設と stack-pack 方式（本 pack の位置づけ）
- ADR-0019: UI/UX ハーネスの段階導入（opt-in pack パターンの原型）
- ADR-0018: 北極星と最小ループ（opt-in・組み立て不要）
- ADR-0020: Spine-Driven の棚卸しと構想凍結（本 pack は Spine柱1 + Observability柱5 の解凍）
