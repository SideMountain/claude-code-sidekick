# ADR-0021: stack pack 方式の確立と Next.js 参照インスタンス

## ステータス

採用（2026-06-17）

## 背景

コードベースを単一 HTML で可視化するスキル（system-map: 画面↔API↔DB↔権限↔遷移）を ccs の配布物にしたい。だが可視化が**決定的に**動く（推測でなく静的解析で「地図が自分で描かれる」）には、下流PJが**既知のアーキテクチャ**で書かれている必要がある。任意のコードベースを逆解析する descriptive 方式では PJ ごとに構造が違い、軟らかい層（LLM 推測）に落ちて「汎用」と「決定的」が両立しない。

解は **prescriptive**: ccs がアーキを規定し下流が従う。規約を固定すればパーサは*その規約*を読むだけで済み、汎用かつ決定的になる。しかしこれは ccs を opinionated にする方向であり、「stack 非依存の軽量思考 OS」という core（ADR-0007 positioning・ADR-0018 北極星）と緊張する。**どう載せれば core を侵さずに深さを得られるか**が論点。

設計探索（参照業務PJ のアーキ最適性評価 + 現行公式ベストプラクティスの裏取り、いずれも敵対レビュー込み）の結果、規定アーキ（golden path）は「良いアーキ」と「パーサ決定性」がほぼ一致することが確認できた。

## 決定

1. **ccs に opt-in な "stack pack" レイヤーを新設する。** UI/UX ハーネス（ADR-0019）の opt-in パターンを「UI 領域」から「フルスタック」へ一般化したもの。`/setup` で申告した PJ にのみ配置し、使わない PJ は無コスト。
2. **stack pack の "方法" は stack 非依存とする。** 「アーキを規定する → 地図が自分で描ける → 強制で守らせる」という方法自体はスタックに依存しない。**Next.js（App Router + Prisma + 認証 + zod）pack はその第一の参照インスタンス**であり、将来 他スタックの pack も同じ方法で別ルールを書く。
3. **core は agnostic のまま一次に保つ。** hooks（安全ガード）・brain（判断の複利）・北極星・skills・知識パイプラインは stack 非依存で全 PJ に効く。stack pack はその上に載る opt-in の上物。
4. **ccs を1スタックに張り替えない。** pack は「参照 stack pack」と明示ラベルし core と峰分けする。core を放置して pack だけ太らせる運用上の重力に対しては、core を一次として保つ規律で対処する。
5. **golden path の規約は出自を明示する。** Next 公式の既定（①）でない規約（②主流 / ③ccs独自）を決定性のため MUST/SHOULD に格上げする箇所は、本文に「公式は recommend 止まり / 標準に無い」+「ccs 決定性のため」を併記する。load-bearing でない規約は SHOULD に留め、過剰規約（北極星「組み立て不要」違反）を自己抑制する。

## 理由

1. **北極星（ADR-0018）**: opt-in・無コスト・pre-wired（規約に乗れば map+規律がタダで付く）で「組み立て不要」を*強化*する。
2. **拡張ファースト**: ADR-0019 の opt-in pack パターンの一般化であり、新レイヤーの発明ではない。
3. **moat 強化**: 強制層・検知層は stack を知ると「規約の適合」まで強制でき、generic な block より深い。system-map は検知層（地図＝drift-gate）、ARCHITECTURE.md は強制層（アーキ規律）のインスタンス。
4. **positioning の連続性（ADR-0007 を extend）**: 「judgment that compounds」の core を上書きせず、その上に stack pack を積む。supersede ではない。
5. **ADR-0020 の解凍**: 凍結した Spine柱1（色宣言→アーキ宣言の一般化）と Observability柱5（system-map）の具体形がこの pack。

## 却下した案

- **ccs を Next.js 専用ハーネスに張り替える（再ベースライン）**: agnostic の物語と moat を失い、勝ち目のない土俵で create-* / Rails と競合する。
- **N スタック分の pack を配るマーケットプレイス**: 1 人の保守者には保守破綻（各 pack は外部標準の進化で陳腐化する）。pack は当面1本（実働スタック）に絞る。
- **pack を core に混ぜる**: core と pack の峰分けが失われ、agnostic 一次・opt-in 上物の構造が崩れる。
- **参照業務PJ のアーキをそのまま golden path に enshrine する**: 評価の結果、骨格（依存方向・命名・test 配置）は健全だが層内規約（ロジック配置・認可・validation）は不統一で、多数派をそのまま規約化すると悪い慣行を固定化する。golden path は「良いコーナーの一般化 + 公式準拠への収斂」とした。

## 影響

- `.claude/stack-packs/nextjs/` を新設し `ARCHITECTURE.md`（golden path）と `README.md`（pack 思想・出自）を配置。
- system-map スキルは Next.js 版への rebuild + 固有名詞 scrub の上で pack 配下へ移す（別作業。現行の Spring/Vue 版は固有名詞を含むため未取込）。
- fitness 関数テンプレ・scaffold・`/setup` 連携は後続 phase（段階導入）。
- ccs core は無変更。本 ADR は配布リポの canonical home に留まり、下流 fork には配布しない（ADR-0014）。

## 補遺（2026-06-18・dogfood 検証による精緻化）

実 Next.js+Prisma 業務 PJ への dogfood（7次元測定）+ 敵対検証（4レンズ・2本目 PJ で n=2 確認）を実施。golden path を**実コードに当てて**検証し、以下を確定した（ADR-0021 の意図の明確化であって supersede ではない）。

### スタンス（確定）

- **OSS（golden path）はベストプラクティスを正とする。既存 PJ に合わせて緩めない。** 既存の非準拠 PJ は **golden path への refactor 対象**であって、規約を曲げる理由にしない（grandfather 機構・migration roadmap は不採用）。
- **減算（過剰だった規約の精緻化）と加算（新たに縛る規約）を分離する。** 実測で「過剰」が裏取れた減算は今行う。実測根拠の無い加算（例 `withAuth` wrapper / `companyId` brand type / fetch URL 静的化の HARD 化）は **SHOULD 止め**とし、HARD 格上げは下流 1 本で遡及コストを dogfood してから。

### 精度訂正（手段と本質の取り違えを正す）

- **S4 の本質は「列挙可能な単一 mutation 機構」**であり、Server Action / route handler はその手段。手段（Server Action か）を MUST に焼くのでなく、**列挙可能性**を MUST にする。Server Action は内部 mutation のベストプラクティスとして維持しつつ、**inline closure を禁止**（grep 列挙が原理的に不能になり本質を壊す）。`n=2`（2本目 PJ は Server Action 多用）でも「列挙可能な単一機構」は耐える。
- **決定性スコープの正直化**: 認可は「gate + 要求 role」と「object-level 認可の**存在**」は HARD、「object-level 認可の**全分岐網羅**」と「行レベル業務認可」は SOFT。`@/*` alias は DX で決定性中立（決定性に効くのは barrel ゼロ + 単方向）。
- **mutation は trigger 別に列挙**（page到達 / scheduler=cron / provider-callback=webhook / internal）。page 非到達の高 blast-radius 入口を取りこぼさない。webhook は idempotency（event-id dedup or 証明可能な冪等）を要件化。

### メタ教訓（記録）

dogfood の分析エージェントは **pack を未インストールの業務 PJ を測定したため、その PJ 独自の規約を golden path と取り違えた**箇所があった。実 `ARCHITECTURE.md` と照合すると指摘の多く（S4 の actions.ts 集約・認可の HARD/SOFT 分離・resilience 境界）は**既に対処済み**で、真の訂正は外科的だった。**dogfood findings は実 spec と照合してから適用する**（findings を盲信して spec を n=1 で動かさない）。

## 関連 ADR

- ADR-0007: thinking OS positioning（extend 対象）
- ADR-0018: 北極星と最小ループ（opt-in・組み立て不要）
- ADR-0019: UI/UX ハーネスの段階導入（opt-in pack パターンの原型）
- ADR-0020: Spine-Driven の棚卸しと構想凍結（本 pack は Spine柱1 + Observability柱5 の解凍）
