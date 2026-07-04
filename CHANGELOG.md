# Changelog

sidekick のリリース履歴。セマンティックバージョニングに従う。
バージョンは git tag + GitHub Releases で管理する。

各PJは `CLAUDE.md` Project Configuration の `SIDEKICK_VERSION` で取り込み済みバージョンを管理し、
`/inventory` で GitHub Releases API 経由で未適用の更新を検知する。

## リリース温度感

各リリースは3段階の温度感に分類される（ADR-0009）:

| 温度感 | マーカー | 意味 |
|---|---|---|
| **Critical** | `⚠️ [CRITICAL]` | セキュリティ / 致命的バグ修正。即取り込み推奨 |
| **Standard** | （prefix なし） | 通常の機能追加・修正（デフォルト） |
| **Enhancement** | `💡 [ENHANCEMENT]` | opt-in な改善。後回し可 |

温度感は GitHub Release の title prefix と body banner に出るほか、body に機械可読な
`severity:` マーカー（`> severity: critical|standard|enhancement`）として出力される。
`/inventory` はこのマーカーを一次ソースとして読み（無ければ title にフォールバック）、緊急度を伝える。
判定は `/release` スキルが切る時に行う。

## [Unreleased]

### Changed

- **難所の能力エスカレーションを「上位モデル前提」から「検証量 ladder」へ再定義**（ADR-0028）: `context-economy.md` §8 の R2 不変条件を「必ず上位モデル」から「単発判断の禁止 + 難所カテゴリ別のエスカレーション ladder（L1 敵対検証 / L2 多視点 3 票 / L3 実行 arbiter / L4 多エージェント裁定 + min()）」に置換。実行は特定 model tier の存在を前提にせず**可用最上位構成**（その環境で使える最上位 model + reasoning effort）で行う。上位 tier の可用性は外部依存であり、消失時に安全機構が silent 縮退する脆弱性を解消する。rules / skills の「上位モデル」表現を「可用最上位構成」に統一。`/auto-implement` に **R4-impl（編集直前ゲート・変更対象を未 Read なら編集前に Read / 新規外部 API は一次ソース確認）**を追加し、docs/rules のみの変更（`/verify` 省略経路）の完了判定に機械確認を最低 1 つ必須化。難所閉集合・ladder・R3 定型の単一ソースは §8 に集約（SKILL からの逐語再掲を撤去）。
- **常駐コンテキストのダイエット**（モデル非依存化 WS6）: 常駐ルール層を再配置し、既定 PJ の常駐フットプリントを **979 → 788 行（−19.5%）** に削減（何も削除せず retrieve-on-demand へ移動）。(1) `task-management.md` の Layer-2（Notion 連携 + 判断ログ同期・66 行）を遅延 doc `.claude/docs/task-db-layer2.md` へ退避（既定 `NOTION_ENABLED=false` では常駐ゼロ） (2) `git-strategy.md` の Worktree 運用手順（76 行）を遅延 doc `.claude/docs/worktree-guide.md` へ退避（H12/H13/H14 の HARD 要約は CLAUDE.md・git-strategy.md に残置） (3) `database.md`・`deploy-strategy.md` を path-scoped 化（DB 関連ファイルに触れる時のみロード・DB 無し PJ では非常駐。H1-H6 は CLAUDE.md 常駐 + `guard-db-operation.sh` 強制で保護不変） (4) `context-economy.md` §4 ⇔ `context-management.md` の compact 閾値の数値不一致（60% vs 50%）を ~60% に統一。**聖域厳守**: HARD 安全ルール・設計 why・必須レビュー観点は常駐維持（context-economy §6）。移動内容は byte-identical で検証（silent drop なし・§7）。
- **知識還流の 4 箇所重複を単一ソースに集約**（モデル非依存化 WS5）: `close-chat/references/knowledge-reflux-guide.md` と `weekly-inventory/references/feedback-compression-rules.md` を skill 固有部分だけに薄型化し、判定 rubric は `.claude/docs/knowledge-reflux.md` を参照。`knowledge-map.md`（致命クラスを 4 カテゴリ閉集合に精緻化）・`auto-implement` Phase 5b・`weekly-inventory` Step 0a/3b も同 doc を指すよう配線。将来の文面乖離バグを構造で防止。
- **`/auto-implement` を指揮者に刷新**（ADR-0027・モデル非依存化 WS3）: 機構を公式部品（plan mode で分解 → `/goal` で完了条件宣言 → 実装 → `/verify` で動作実証 → `/code-review`+`/review` アダプタで裁定）に委ね、ccs は無人実行の安全の要だけを担う。(1) Phase 0 入口ゲートを **R1 rubric（7 問・1つでも NG→停止）**に置換し、未決定マーカー・曖昧語・migration パスを機械 grep で判定 (2) budget-gate 連動で **THROTTLE 時は fan-out 幅（並列本数・敵対検証の票数）のみ縮退**し、縮退を **progress ledger（ADR-0024）に明示**（silent drop 禁止） (3) **難所の閉集合 R2 + 敵対検証 R3** を配線し、`/review` の verdict をそのまま採用（再判断禁止）・矛盾 findings は多視点 judge へ fan-out。R8 trivial-gating で fan-out 発火を機械判定。SKILL.md はレポート実例を `references/report-examples.md` へ分離。
- `.claude/rules/context-economy.md` §8 を改訂: 難所の閉集合（R2）+「判定に迷う場合も難所（上位既定）」+ 敵対検証（R3）の定型を明文化（`/auto-implement` 他が参照する単一ソース）。
- `/setup` に無人稼働の opt-in 導線を追加（ADR-0026 の `/setup` 配線）: `SIDEKICK_AUTO=true` の起動コマンドを案内し、隠しトグル化を回避。
- **`guard-bash.sh` の `AUTO_MODE` 既定を `true` → `false` に変更**（ADR-0026 Accepted）: 対話セッションは既定で H7/H8 を厳守（feature push / 非保護 merge も確認）。無人稼働は起動コマンドが内包する `SIDEKICK_AUTO=true` で明示 opt-in（隠しトグルにしない導線）。ハードブロック（保護ブランチ・`.env`・`rm -rf`・PRD DB 等）は AUTO_MODE 非依存で不変。既定 `false` により「必ず確認」（HARD 文言）と guard 既定が一致する。実機検証済（3 設定 × 3 コマンド）。
- **review 系 6 スキルを 1 アダプタに統合**（ADR-0027・モデル非依存化 WS2）: `/review` を「決定的 fitness → 公式 `/code-review`（REVIEW.md 規範注入）→ min() 総合判定」の薄いアダプタに刷新。機構は公式に委ね、ccs は PJ 規範（HARD照合・ADR整合・破壊的変更・a11y・hook教訓）と最終ゲート（min）だけを持つ。`/review` SKILL.md は 203→105 行。
- `.claude/skills/review/references/scoring-guide.md` を severity→min() モデルに整合（rubric 既在だが未配線だった最終判定の配線を解消）。

### Added

- **難所の機械 force-flag**（ADR-0028 決定3）: `.claude/scripts/detect-hard-spot.sh` — 変更パス（`.claude/hooks|githooks|scripts/`・`settings*.json`・`prisma/`・`migrations/`・`*.sql`・auth/session/token 等のパス名）と変更行（`AUTO_MODE`・`SIDEKICK_AUTO`・`PROTECTED_BRANCHES`・`DATABASE_URL`・破壊的 DDL）を決定的に grep し、ヒットしたら**モデルの自己判定に関わらず難所として扱う**（force-flag）。advisory・常に exit 0・pure grep（jq 不使用）・複数スキルから参照する共有配置。BASE 解決と diff 取得は `review-fitness.sh` を踏襲。
- **知識還流の判定リファレンス（単一ソース）**（モデル非依存化 WS5）: `.claude/docs/knowledge-reflux.md` に R5（同趣旨ペア判定・2/3 YES）+ R6（昇格判定・3/4 YES + 致命クラス 4 カテゴリ閉集合）+ R7（還流 3 分類）+ few-shot コーパス（昇格した/しなかった実例）を集約。`/close-chat`・`/weekly-inventory`・`/auto-implement`・`rules/knowledge-map.md` の 4 箇所に別文面で散っていた昇格・還流判定を単一ソース化（診断: ライフサイクル系横断 DRY #1）。標準モデルでも rubric + few-shot で昇格判定がぶれない。`.claude/docs/` は遅延ロードで常駐しない。
- **公式スキル鮮度 watch**（ADR-0027 決定4・モデル非依存化 WS7）: `/weekly-inventory` に Step 5d を追加し、公式スキル採用を継続追随プロセスとして常設。`.claude/skills/weekly-inventory/scripts/official-freshness.sh` が稼働 CLI と各ラッパー（`/review`・`/auto-implement`・`/setup`）の参照する公式 feature の version floor（`hook-helpers.sh` の single source of truth）の drift を機械検知（fail-open）。新規公式スキル・挙動変更は news-upstream / 公式リリースノートを一次入力に照合し、gap を `gh issue create`（ラベル `official-adoption`）で逆流ループに載せる。`hook-helpers.sh` に `ccs_official_features`（feature 列挙・floor リストと同期）を追加。
- `REVIEW.md`（リポルート）: 公式 `/code-review` へ PJ 規範を注入するファイル。`/setup` が下流 PJ 向けに配置・調整する（Step 3e / Step 2E）。
- `.claude/skills/review/scripts/review-fitness.sh`: 破壊的マイグレーションキーワード・a11y（alt/label 欠落）・空 catch を決定的に検出する前置ゲート（破壊的キーワード検出の 4 重定義を 1 本化）。
- `docs/migrations/`: 下流移行ガイドの標準ディレクトリ（初適用: `review-6to1-adapter.md`）。

### Deprecated

- `/review-code` `/review-test` `/review-ops` `/review-design` `/review-spec`: `/review` アダプタに統合。deprecation スタブ（`/review` への委譲を案内）を 1 リリース残し、次のマイナーで撤去する（移行: `docs/migrations/review-6to1-adapter.md`）。

### Removed

- `.claude/skills/review/agents/review-agent-template.md`: 5 観点 fan-out 廃止に伴い撤去。

## [0.12.0] - 2026-07-02

信頼性（強制層を約束に追いつかせる）＋文脈経済スイートのリリース。強制層ガードのバイパス修正を含むため **⚠️ [CRITICAL]（即取り込み推奨）**。破壊的変更なし・既存 PJ は無設定で従来動作を維持する。文脈経済・自律ループ系は opt-in（`💡 [ENHANCEMENT]`）。

### Added

- 💡 [ENHANCEMENT] 文脈経済（Context Economy）ドクトリン（ADR-0023）: rate-cap 内で精度を落とさず長時間・自律稼働するためのトークン経済原則。`per-call context hygiene`（不要文脈を渡さない）を最優先に置き、モデル自動選択（tiering）は精度優先で補助レバーに留める。
- 💡 [ENHANCEMENT] `.claude/rules/context-economy.md`: 安全コア規律（per-call hygiene / cache を壊さない / retrieve>resident / fan-out は難所だけ / 削らない聖域 / lossy には検知層）。
- 💡 [ENHANCEMENT] `/token-audit` skill: 常駐コンテキストの footprint 計測・汚染/肥大/重複検知・公式 rate_limits（statusLine stdin）の実データ読取り（文脈経済の検知層）。配布コアスキルが 17 → 18 本に。
- 💡 [ENHANCEMENT] 自律ループ + budget-gate 設計（ADR-0024）: 自律稼働を rate-cap 内で長時間・安定に回す設計（状態の disk 外部化 + サイクルリセット / Stop 境界での段階制御 / 精度の聖域 / fail-open）。AUTO_MODE 既定値のポリシーは ADR-0026 で審議中（本リリースでは既定を変えない）。
- 💡 [ENHANCEMENT] `.claude/hooks/budget-cycle-halt.sh` を `Stop` に配線（ADR-0025）: rate 使用率に応じ &lt;60% 無出力 / 60–85% 助言のみ / &gt;85% で Stop 境界に ledger+commit を促して次サイクルを休止する強制面。capturer が新鮮なデータを書けているときだけ発火し、不在・stale・パース失敗は NORMAL に fail-open（capturer 未配線の PJ は無コストで休眠）。session_id 別マーカーで再入ガードし無限ブロックを防止。WSL 実機で発火・冪等・fail-open・安全ガード非短絡を検証済み。
- 💡 [ENHANCEMENT] `.claude/statusline/ccs-rate-capture.sh`: capturer（公式 rate_limits を正準ファイルへ保存するデータ面）。hook は rate_limits を読めないため強制層の唯一のデータ橋。budget-cycle-halt.sh はこの正準ファイルを読む。
- 配布テンプレ `.claude/templates/github/ISSUE_TEMPLATE/downstream-feedback.yml`: `.github/` にのみ存在し配布側に欠落していた下流フィードバック用 Issue テンプレを追加（`.github/` 版と byte 一致）。

### Changed

- **PROTECTED_BRANCHES を設定化（信頼性・ADR-0023 系の強制層整合）**: `guard-bash.sh` / `guard-protected-branch-edit.sh` / `session-start.sh` の保護ブランチ `"main"` ハードコードを廃し、`hook-helpers.sh` の共通リーダ `get_protected_branches()` 経由で CLAUDE.md Project Configuration の `PROTECTED_BRANCHES` リストから読む（`SIDEKICK_PROTECTED_BRANCHES` env 上書き可・既定 `"main"`・fail-safe）。STG 運用 PJ で認知層（CLAUDE.md）と強制層（hooks）が乖離し release/stg が保護されないバグを解消。**設定が無い既存 PJ は従来どおり main のみ保護（後方互換）**。printf/awk ベース（echo 不使用）・slash 安全な `_branch_in_set()` で membership 判定。
- ドキュメントのスキル数を実数 18 に統一（README 両言語 / `docs/lifecycle.md` 両言語 / `three-layers` SVG 両言語）。スキル一覧表に `/token-audit` を明記。`lifecycle` の実体確認スタンプと README の `SIDEKICK_VERSION` 例を 0.12.0 に更新。

### Fixed

- ⚠️ [CRITICAL] **強制層ガードの正規表現バイパスを堅牢化（`guard-bash.sh` / `hook-helpers.sh`）**: DENY 判定が「クォート除去後の生文字列への正規表現マッチ」に依存していたため、自明な変形でガードを素通りできた。以下を修正（各修正に模擬入力の回帰テストを用意）。
  - **C-1 `git -C <dir>` 等のグローバルオプション経由**: `git -C . push origin main` / `git --git-dir=… checkout main` がサブコマンド判定をすり抜けた。`normalize_git_cmd()`（`hook-helpers.sh` 新設）で `-C` / `-c` / `--git-dir` / `--work-tree` / `--namespace` 等のグローバルオプションを除去し、正規化後の文字列で checkout / switch / push ガードを判定。
  - **C-2 shell executor 経由**: `bash -c '…'` / `sh -c "…"` / `eval` / `xargs` はペイロードがクォート内にあり、クォート除去で消えて破壊系ガードを素通りした。破壊系ガード（rm 再帰 / 保護ブランチ push / `prisma db push` / `.env` 書換）は executor 検知時に生 COMMAND も併せて判定。executor の存在自体は警告（破壊系トークンが生 COMMAND に無い限り DENY はしない＝誤検知回避）。
  - **H-1 保護ブランチ push の末尾トークン依存**: `git push origin main --quiet` / `-v origin main` / `origin main;` / `origin HEAD:main -v` が行末 `$` アンカーを外れ AUTO 許可されていた。`push_targets_protected_branch()`（新設）で push 引数のトークン列を走査し、`src:dst` の dst・`refs/heads/` 接頭辞・先頭 `+` を解して判定（アンカー非依存・`--force` 有無非依存・連鎖コマンドは segment 単位で走査）。
  - **H-2 `rm -Rf` / `find -delete`**: 大文字 `-R` や結合フラグを取りこぼしていた再帰判定を `-[rR]` 大小両対応の結合フラグ対応に。`find … -delete` / `find … -exec rm` を警告対象に追加。
  - **L-1 `git switch`**: checkout ガードを回避できた `git switch main` を（C-1 正規化後に）checkout ガードへ統合。
  - **M-1 `.env` writer 取りこぼし**: `printf … > .env` / `cat > .env` / `cp x .env` を Guard4 が拾えなかった。writer 集合に `printf` を追加し、任意コマンドのリダイレクト先 `.env`・`cp`/`mv` の宛先 `.env` を検知（`.env.example` / `.env.local` は非対象）。
  - 方針: AUTO_MODE 既定値（ADR-0026 で審議中のポリシー）は変更せず、バグ修正に限定。判定文字列の抽出に失敗しても破壊系は安全側（確認 / DENY）に倒す fail-safe を維持。既存 7 挙動の回帰・正常系の誤爆なしを確認。
- `.claude/agent-memory/MEMORY.md` に残存していた旧スキル名 `/weekly-review` を現名 `/weekly-inventory` に是正（0.6.0 の rename 積み残し）。

### 変更された ADR

- `docs/decisions/0023-context-economy.md`（0.12.0 で初リリース）
- `docs/decisions/0024-autonomous-loop-and-budget-gate.md`（0.12.0 で初リリース）
- `docs/decisions/0025-budget-gate-stop-hook-wiring.md`（新規・Accepted: Stop hook を gating+fail-open で配線・WSL 検証済み）
- `docs/decisions/0026-auto-mode-default.md`（新規・Proposed: AUTO_MODE 既定値の意思決定）
- `docs/decisions/README.md`（索引更新）

## [0.11.1] - 2026-06-20

### Fixed
- **greenfield bootstrap を実走検証して是正（README の「Building a Next.js + Prisma project」を実際に通した）**: scaffold を create-next-app の土台に重ねる経路を temp PJ で end-to-end 実走し、破断点を是正。(1) `scaffold.js` が既存 `package.json` を**破壊的に上書き → 非破壊マージ**に変更（app `name`・解決済み依存バージョンを保持し、`test:arch` 等の golden path script と不足依存〔`@prisma/client`/`zod`/`server-only`/`prisma`〕だけ追加）。(2) create-next-app の既定 `app/page.tsx`/`app/globals.css`（golden path 外・余分な screen `/` になる）と別形式 config（`next.config.js` 等）を検知して後始末を促す post-run note を追加。(3) 不正な既存 `package.json` を clean error で弾く guard。空ディレクトリ展開は従来どおり（回帰なし・fitness `verify.js` / system-map `verify-adapters.js` 32/32 自己検証 PASS）。
- **doc 事実誤りの是正（README/lifecycle/skills・EN/JA）**: (a) `/review` を「6 観点」→**実体どおり「5 観点」**（code/test/ops/design/spec + PJ固有）。README 本文・**hero SVG（`three-layers.svg`/`.ja`）**・**`review/SKILL.md`**（4 と 6 の自己矛盾も解消）を統一。(b) walkthrough step 4 の `--force` を「任意」→**create-next-app 後は必須**と明記 + 非破壊マージ / config 置換 / leftover 後始末を追記。(c) step 5「`prisma/schema.prisma` を先に書く」→**scaffold が posts モデルの schema を同梱**するため「拡張する」に訂正。(d) `lifecycle` open-loop #7 の「system-map は staleness 検出器なし / route・authz adapter は roadmap」を**実体（#57 drift 信号 + #56 adapter 出荷済・`route-enumerator` 共有）に更新**。(e) `SIDEKICK_VERSION` 例 / `lifecycle` 検証 / `setup` 案内のバージョンを 0.10.0 → 0.11.0。(f) `system-map` SKILL に「再生成時の stale 掃除」gotcha（`merge.js` は `data/*.json` を全 glob する）。

### Removed
- **死んだ `.husky/* text eol=lf` ルールを `.gitattributes`（本体 + `.claude/templates/.gitattributes`）から削除**: `.husky/` は v0.11.0 までに削除済（`core.hooksPath=.claude/githooks`）で、この line-ending ルールは存在しないディレクトリを指す cruft だった。templates 版は下流に配布されるため両方を掃除。

## [0.11.0] - 2026-06-19

### Added
- **ADR-0022: stack pack のサイクル統合・軽さドクトリン・intake routing**（原則決定・配線は follow-up）。stack pack は普遍サイクルのゲート（`/review`・`/auto-implement`・hooks）に自動統合し下流はフラグ1個（CI 配線させない）/ 軽さドクトリン（自動化は決定的・安いものだけ・LLM は on-demand）/ ①起票 = backlog（個人）・GitHub Issue（チーム機能/bug/可視化）・Notion（任意）の三層 routing + casual「Issue だけ切る」一級化 + 1アイテム1ホーム + backlog→Issue 昇格。capability audit の「下流が CI を持つ」暫定スタンスを supersede、ADR-0018/0021/0015 を refine。
- **`/review` に architecture fast-gate（ADR-0022 follow-up a）**: `STACK_PACK=nextjs` かつ関連ファイル（`app/`・`lib/`・`components/`・`prisma/`）変更時のみ `run-fitness.js` を決定的に実行（**6 個目の LLM 観点にしない**・error=BLOCKER / warn=WARN / 対象外・`none`・pack未同期=沈黙 fail-safe）。下流は CI 配線なしで `/review` がアーキ逸脱を自動検知（サイクル不変・stack 可変・`STACK_PACK=none` は no-op）。
- **system-map の硬層 adapter 群を新設（ADR-0022 follow-up b）— 地図が code から決定的に描かれる**: 従来 hard 層は `extract-indexes`（Prisma 索引）1個のみで、画面/API/mutation/認可/遷移の骨格は LLM サブエージェント or 手書き依存だった。新たに **`extract-routes`**（screen + api を `kind`★S4/`trigger`/`validation`/`dbTablesRead-Write`(DAL コールグラフ)/`calledByScreens` 付きで `<domain>.json` に）・**`extract-authz`**（Prisma enum の roles + `requireSession`/`requireRole`/out-of-band realm〔webhook 署名・cron secret〕/`spaGuards` → `permissions.json`）・**`extract-links`**（`Link`/`router.push`/`redirect` → flow edges）・**`extract-schema`**（列・型・PK/FK・relations・`accessedFrom` の 1:N → `db-schema.json`）を同梱。**正準カウントは `fitness-functions/lib/route-enumerator.js` を import**（fitness と地図が同じ母集合を見る・二重定義しない）。adapter は merge.js が既に食う既存形を吐くので merge は無改修・軟層は同名ファイルの enrich overlay に。**co-validation**: `verify-adapters.js` が scaffold golden slice（conforming fixture）に全 adapter を実走 → 期待値 + 正準カウント突合 → merge+build+verify PASS を保証（生成器=scaffold・検知器=fitness・描画器=verify が同じ fixture を共有 → drift 不能）。
- **system-map の drift 信号を `/review` に配線（ADR-0022 follow-up b・タイミング = C+A）**: 地図の**生成は手動 `/system-map` のまま**、`/review` の fast-gate が「地図が古い」を**検知して 1 行 nudge**（認知→検知の背骨）。`fitness-functions/canonical-counts.js`（正準 enumerator のカウントを JSON 出力 + `--drift <snapshot>` で差分 1 行）を追加。`/system-map` 生成時に `.claude/.system-map-counts.json`（per-dev の鮮度マーカー・gitignored）を刻み、`/review` Step 1.6 が現在のコードと比較して構造変化時のみ surface（snapshot 無し・構造不変・`STACK_PACK=none` は沈黙／count は fast-gate と同一 enumerator で追加コスト皆無）。**毎マージ自動再生成（hook）は不採用**: 地図はゲートでなく可視化物で、未消費の成果物を作り続けるのは軽さドクトリンに反するため。
- **`docs/lifecycle.md`（EN/JA）新設 — ccs 全体の「ライフサイクル地図」**: 全機能を 8 つのライフサイクル輪に配置し、各輪が**閉じているか/開いているか**を明示（capability audit 由来）。閉6（session・知識複利・dev・release→adopt・強制×3・逆流）/ 開2（stack-pack 検知→再実行は下流 CI 委譲・upstream-watch は保守者専用 news-upstream で非配布）+ 全機能インベントリ表。README から導線。

### Changed
- **intake routing を実運用化（ADR-0022 follow-up c+d）**: `/close-chat` に「Issue化」選択肢 + casual「これ Issue にして」起票 + 1 アイテム 1 ホーム + backlog→Issue 昇格。`rules/task-management.md` に intake routing 表（backlog=個人/working / GitHub Issue=チーム機能・bug・可視化 / Notion=任意）を追加、`rules/knowledge-map.md` の積み残しタスク routing を backlog/Issue に分岐。
- **README を「点の羅列」から「輪」へ refinement（EN/JA）**: 強制層 hooks インベントリを可視化（従来 `guard-bash.sh` のみ→`session-start`/`prompt-reminder`/commit本文 guard/PII pre-commit を明記）/ 下流逆流ループを Feedback 節で接続（Issue 3種リンク + `/inventory`→backlog→`/release`→`/adopt` の閉じ方を1行）/ skills 表に `system-map`（opt-in）注記 / `lifecycle.md`・ADR 索引へのリンク / `SIDEKICK_VERSION` 例を 0.10.0 に更新。`scaffold.js` の post-copy 手順に system-map（可視化）を追加。
- **cruft 掃除**: 死んでいた `.husky/pre-commit` + `.husky/pre-push` を削除（`core.hooksPath=.claude/githooks` で経路外・本物の PII pre-commit と矛盾する囮）。`.gitignore` で旧 top-level `.claude/skills/system-map/`（port 残骸・固有名詞含む）を誤コミット防止にガード。
- **新規 Next.js+Prisma PJ のオンボーディングを README で完結させた（EN/JA 両方）**: v0.10.0 で出荷した stack-pack アプリ層（`STACK_PACK` フラグ・scaffold・fitness `test:arch`・`ARCHITECTURE.md`）が README/`/setup` に未記載だった doc gap を解消。README に `STACK_PACK` 設定行 + 「Building a Next.js + Prisma project」通し手順節を追加（README.md / README.ja.md）。`/setup` Step 3d を拡張（scaffold コマンド・`test:arch` の package.json 配線案内・**生成直後で package.json 不在の chicken-and-egg を直接確認にフォールバック**）。`docs/design.md`/`.ja` の stack pack 節に scaffold + fitness を明記。

### Fixed
- **fitness が `.claude/` を走査して H4 を誤検知する問題を修正（greenfield 検証で発見）**: pack を取り込んだ下流で `run-fitness .` を回すと、同梱された pack 自身のテスト fixture（`fixtures/violations/h4/stale.backup`）を H4 の `.backup` 走査が拾い spurious error を出していた。`SKIP_DIRS` に `.claude` を追加し、ccs ツール群（PJ の source でない）を走査対象外に。回帰 fixture（`fixtures/falsepos/claude-skip`）+ verify アサーション追加。pack verify は回帰なし・実 `app/` 配下の逸脱検知は維持。

## [0.10.0] - 2026-06-18

### Added
- **Next.js stack pack に fitness-functions（検知層）+ scaffold（強制層）を新設**（`.claude/stack-packs/nextjs/`）。「認知（ARCHITECTURE.md）→ 強制（scaffold）→ 検知（fitness）」が揃い、下流 Next.js PJ は **opt-in 一発で golden path に乗り・地図が描け・違反が CI で止まる**。
  - **`fitness-functions/`**: `ARCHITECTURE.md` の各 MUST を grep-checkable assertion として実装（依存ゼロ plain Node・S1-S7/H1/H3/H4）。`run-fitness.js`（主・WSL 安全な単一プロセス・`error` で exit 1）+ 下流向け vitest ラッパーテンプレ（`templates/architecture.test.ts`）。`severity` を **error=HARD / warn=SOFT 残差**に分け、決定性スコープの正直な約束をコードでも守る。escape hatch（`// barrel-ok` / `// authz-ok`）。
  - **正準 route-enumerator を単一モジュール化**（`fitness-functions/lib/route-enumerator.js`）: route/screen/server-action/cron/mutation 面の母集合を**唯一の正準定義**に凍結（route 数の数え方ぶれ 87/88/92/93/112 を解消）。fitness と（後続の）system-map route adapter が同参照（DRY）。
  - **`scaffold/`**: golden path skeleton 生成器。`template/`（規約を満たす具体 `posts` 縦スライス）を展開し、新規 PJ を最初から規約に乗せる。**`template/` は fitness の conforming fixture と同一ファイル**＝scaffold 出力 ≡ fitness green を物理的に保証（契約と生成器が互いの受け入れテスト・ドリフト不能）。
  - **自己検証**（`fitness-functions/verify.js`）: conforming=error 0/warn 0・全 violation fixture で該当ルール発火を機械的に保証（system-map `verify.js` と同じ規律）。
- **checker 自身に「コメントを一次ソースにしない」を適用**: fitness の静的走査を**文字列・正規表現リテラル保護付き** comment-strip 前処理に変更（コメント内の規約名 `usePathname()` / `new PrismaClient` 等の誤検知、および URL 正規表現 `/^https?:\/\//` の `//` が同一行の実違反を潰す false-negative を根治）。methodology の硬層 adapter 原則を checker にも適用。

### Changed
- **H1 の接続文字列ログ検知を精緻化（実 PJ dogfood 由来）**: 実 Next.js+Prisma コードベースへの read-only dogfood で、`console.log('DATABASE_URL exists:', !!process.env.DATABASE_URL)` 等の**ラベル・存在チェックを値ログと誤判定する false-positive** を検出。`process.env.DATABASE_URL` の**値**を否定なしで出す bare ログのみ error、その他の DATABASE_URL 言及（ラベル / 存在チェック / preview）は warn（値漏洩でないか要確認）に分離。verify に false-positive 回帰 fixture（`fixtures/falsepos/h1-existence`）を追加し、checker が正当コードを error にしないことを保証。

## [0.9.0] - 2026-06-18

### Added
- **stack pack の opt-in wiring**（下流取り込み導線）: CLAUDE.md Project Configuration に `STACK_PACK`(none|nextjs) フラグ新設 + CLAUDE.md に opt-in gate（`STACK_PACK=nextjs` で `ARCHITECTURE.md` の golden path に従う・`none` は無コスト）。`/setup` に Step 3d（Next.js 検知時のみ opt-in 案内）。`/adopt-sidekick-update` に opt-in aware な配布（`STACK_PACK≠none` の PJ にのみ stack-packs を同期＝非 Next PJ に clutter を配らない）+ 深いネストパス対応（`mkdir -p`）。`design.md`/`design.ja.md` に stack pack 節を追加。非 Next PJ はコストゼロ・Next PJ は明示 opt-in（ADR-0021）
- **Next.js stack pack（opt-in 参照 pack）新設**（`.claude/stack-packs/nextjs/`）: `ARCHITECTURE.md`（規定アーキ＝golden path・Tier-1 STRUCTURAL/Tier-2 HYGIENE・①公式/②主流/③ccs独自・MUST/SHOULD・grep 検証付き）+ `README.md`（pack 思想・出自・roadmap）。現行公式（Next 16.2.9 docs・2026）で裏取り。`system-map` 可視化スキルの決定的動作を支える規定アーキ。stack pack 方式（アーキ規定→決定性→強制）は stack 非依存で Next.js は第一インスタンス
- **`system-map` 可視化スキルの Next.js 土台を pack 配下に同梱**（`.claude/stack-packs/nextjs/skills/system-map/`）: コードベースを「画面↔API↔DB↔権限↔遷移」の単一 HTML 地図に可視化。スタック非依存の骨格（template/merge/build/verify）+ Next.js 化（SKILL/schema/methodology・`api.kind: route-handler|server-action`★S4）+ 硬層 adapter `extract-indexes.nextjs.js`（Prisma schema パーサ）+ generic サンプル（blog/CMS）。`verify.js` で自己検証（35/35 ルート描画 PASS）。固有名詞 scrub 済。残 adapter（ルート/mutation/認可 走査）は段階導入
- `/tune` スキル新設: PJ健全性テコ入れ（テスト実行/CI高速化・テスト棚卸し〔削除せず統合/補強/格上げ〕・コード共通化）を read-only 監査 → 人手ゲートで是正。`weekly-inventory` の兄弟（パターンD）。安全ガードレール（テスト削除提案ゼロ / E2E除外 / 夜間ループ対象外 / mutation を削除根拠にしない）を references に明文化
- `.claude/rules/oss-doc-authoring.md`: OSS ドキュメント作法ルールを配布物に追加（単一リポ化 ADR-0006 に伴い開発リポから移行）

### Changed
- **Next.js stack pack を dogfood で精緻化**（ARCHITECTURE.md / system-map / ADR-0021）: 実 Next.js+Prisma 業務 PJ への dogfood（7次元）+ 敵対検証（4レンズ・n=2）の結論を反映。**スタンス確定: OSS=ベストプラクティス正・既存 PJ=refactor 対象（legacy に合わせて緩めない・grandfather 不採用）**。S4 を「列挙可能な単一 mutation 機構」を本質に再定義（Server Action は維持・**inline closure 禁止**・cron/webhook を trigger 別に列挙）。決定性スコープを正直化（object-level 認可は存在=HARD/全分岐網羅=SOFT、`@/*`=DX 中立）。webhook idempotency・resilience 境界を要件化。system-map schema に `api.kind`(+webhook/cron)・`trigger`・`validation`・`idempotency`・model `accessedFrom` を追加（HTML バッジ + replay 注意表示）。減算（精緻化）は今・加算（withAuth/brand 等の HARD 化）は下流 dogfood 後に分離。自己検証 verify 41/41 PASS
- `/release`: 説明・目的・「いつ使うか」を単一リポ（ccs）前提に統一（二リポ連動の記述を削除）
- `/review`: 公式 bundled スキル（`/code-review`・`/simplify`・`/verify`・`/security-review`）との使い分け Note を追加（置き換えでなく補完。新スキルは作らない）
- `skill-agent-design.md`: 公式標準と突合し最新化 — §7 の判断軸（宣言的 `context: fork` vs 手続き的 Agent 委譲）に加え、`context: fork`=安定・カスタムサブエージェント=推奨へ是正、frontmatter 追補（effort/paths/hooks 等）、冒頭に「最終検証」スタンプを追加。さらに 2026-06-17 に公式 docs（skills.md / sub-agents.md）で再裏取りし、`agent:` フィールド（`context: fork` 時の subagent 種別・公式文書化済み）の確度を是正、frontmatter 表に `disallowed-tools`・`when_to_use` 等を補完
- `brain/thinking.md`（OSS テンプレ）: weekly-inventory で昇格判定した設計原則を追記（dogfood=検知層 / リリース前ローカル検証 / 手動手順は仕組み化のサイン / 配布物の自己完結 / 媒体別の視認性 / 動作担保は実装で検証）
- `knowledge-map.md` / ADR-0006: 知識昇格の3件ルールに「クリティカル class は N=1 でも記録」例外を明文化 + release/tag は配布リポに集約する旨を補足

### Removed
- `/sync-oss` 連動の記述を退役（単一リポ化 ADR-0006）。`/release` の Step 7（二リポ連動）と関連 gotcha/参考、`pii-prevention.md` の sync-oss 自動実行行を削除

### Fixed
- `docs/images/three-layers.svg` / `three-layers-ja.svg`: Layer 2 のスキル数表記を実数に是正（15 → 17・README と整合）

## [0.8.1] - 2026-06-14

### Added
- PII 強制層の pre-commit hook（`.claude/githooks/pre-commit`）— 公開ファイルへの個人情報・固有名詞の混入を commit 時にブロックする。`core.hooksPath .claude/githooks` で各環境が有効化（`/setup` が案内）。単一リポ化（ADR-0006）の前提となる強制層
- 設計思想ダイジェスト `docs/design.md` / `docs/design.ja.md`（評価者向け・番号なし・mermaid 図解、EN/JA パリティ）
- ADR-0006: 単一リポ統合 — 開発と配布を1リポに集約（旧2リポ運用を supersede）
- ADR-0018: 北極星と最小ループ — 能動層は3動詞、他は配管に徹する設計指針
- ADR-0019: UI/UX ハーネス 3 層 — design-system / 検知 hook / VRT の段階導入

### Changed
- README / README.ja を北極星（最小ループ）中心に再構成し、mermaid 等でビジュアル強化。設計思想ダイジェスト `docs/design.md` への導線を追加
- cron / playwright セットアップガイドを刷新（ASCII 図 → mermaid、安全策を表化）。CHANGELOG の温度感 legend を表形式に整理
- リリース severity を機械可読マーカー化（Release body に `> severity: …` を必須出力）。`/inventory`・`/adopt-sidekick-update` がマーカーを一次ソース化（title フォールバックで後方互換）
- README / README.ja を v0.8 実体へ同期（skill 数 16・2層 brain・入手経路・更新受取）

### Fixed
- `/setup`: 新規/既存PJで `SIDEKICK_VERSION` を ccs 最新タグから自動スタンプ（空のままだと `/inventory`・`/adopt-sidekick-update` がスキップされ、新規PJが更新を取り込めなくなる deadlock を解消）
- `/setup` Step 4.5: PJ 固有 brain を決定論的に生成（markdown 例示のみ → 冪等・非上書きの bash 生成ブロックへ。真の新規 PJ で brain 生成が漏れるのを防ぐ。fork 由来の既存 brain は保護）
- `.claude/brain/thinking.md`: 旧3層（L2・ADR-0013）の stale 残骸を 2層 PJ brain（ADR-0016）に置換

### 変更された ADR
- `docs/decisions/0006-single-repo-consolidation.md` (新規)
- `docs/decisions/0018-north-star-and-minimal-loop.md` (新規)
- `docs/decisions/0019-uiux-harness-three-layer.md` (新規)
- `docs/decisions/0009-release-adoption-design.md` (severity マーカー補足)
- `docs/decisions/README.md` (索引更新)

### 変更された rules
- `.claude/rules/pii-prevention.md`

### 変更された skills
- `.claude/skills/setup/SKILL.md`
- `.claude/skills/inventory/SKILL.md`
- `.claude/skills/adopt-sidekick-update/SKILL.md`
- `.claude/skills/release/SKILL.md`

### 変更された hooks
- `.claude/githooks/pre-commit` (新規)

## [0.8.0] - 2026-05-09

### Added
- ADR-0016: brain の 2 層モデル化と上書き禁止運用（ADR-0013 を一部 supersede。3 層 chain → 2 層構造、個人 brain の自動上書き禁止）
- session-start hook: 個人 brain（`~/.claude/brain/thinking.md`）の存在チェック追加（不在時 warning）

### Changed
- brain 構造: L0/L1/L2 の 3 層 chain → 2 層モデル（個人 brain + PJ 固有 brain）+ 単純 1 段 `@import`
- `brain/thinking.md` の位置づけ: 個人 brain の初期テンプレート素材としてリポ内に配置（ロード対象外）
- `.claude/brain/thinking.md`: PJ 固有 brain として再定義（個人 brain を `@~/.claude/brain/thinking.md` で 1 段 import）
- `CLAUDE.md` §1: 2 層モデル + 1 段 import の説明に更新
- `.claude/rules/knowledge-map.md`: 2 層モデルに対応、還流タグ刷新
- `/setup` Step 4.5: 個人 brain 不在時のみテンプレートから初期化、既存個人 brain は上書き禁止
- `/adopt-sidekick-update` Step 6.5: テンプレート更新時は差分提案のみ（自動上書き禁止）
- `/close-chat` `/weekly-inventory` の還流タグを 2 層化（references も同期）
- ADR-0013 ステータスを「一部 Superseded by ADR-0016」に更新

### Breaking Changes
- 還流タグ: `[L0候補]/[L1候補]/[L2固有]` → `[OSS 還流候補]/[個人 brain 昇格]/[PJ 固有]`
- 個人 brain は `/adopt-sidekick-update` で自動上書きされなくなる（差分提案のみ）
- 既存利用者は `/adopt-sidekick-update` 実行で `<PJ>/.claude/brain/thinking.md` の `@import` 行が `@~/.claude/brain/thinking.md` に統一される

### Notes
- 過去取り込みで `<PJ>/brain/thinking.md` が PJ ローカルに残っている場合、v0.8.0 でロード対象外になる。**残骸は害なし**（@import 対象でないため context に乗らない）。自動清掃は v0.8.x で対応予定
- **ロールバック互換性**: v0.8.0 → v0.7.x ロールバックは安全。個人 brain は `~/.claude/brain/thinking.md` に残るため、v0.7.x の chain 構造でも transitive import として機能する

### 変更された ADR
- `docs/decisions/0016-brain-two-layer-model.md` (新規)
- `docs/decisions/0013-brain-three-layer-structure.md` (Superseded by 0016)
- `docs/decisions/README.md` (索引更新)

### 変更された rules
- `.claude/rules/code-quality.md`
- `.claude/rules/knowledge-map.md`

### 変更された skills
- `.claude/skills/adopt-sidekick-update/SKILL.md`
- `.claude/skills/close-chat/SKILL.md` + `references/knowledge-reflux-guide.md`
- `.claude/skills/setup/SKILL.md`
- `.claude/skills/weekly-inventory/SKILL.md` + `references/feedback-compression-rules.md`

### 変更された hooks
- `.claude/hooks/session-start.sh`

## [0.7.4] - 2026-05-05

### Added
- ADR-0015: 下流 PJ の ccs 不意識運用原則（`/inventory` + `/adopt-sidekick-update` のみで取り込み完結、残骸自動清掃、手動手順禁止）
- `/adopt-sidekick-update` Step 6.4d 拡張: ファイル名照合 + 内容完全比較で sidekick 由来 ADR 残骸を自動検知し、デフォルト [Y] で削除提案。`docs/decisions/README.md` の索引行も自動的に削除
- `/setup` Step 0.5 改修: 新規 PJ テンプレート fork 検出時に sidekick 由来 ADR を一括削除し、`docs/decisions/README.md` を空索引に初期化
- `release-format-spec.md` に手動操作禁止原則セクションを追加（リリースノートに下流 PJ への手動手順を含めない）

### 変更された ADR
- `docs/decisions/0015-downstream-ccs-unaware-operation.md` (新規)
- `docs/decisions/README.md` (索引更新)

### 変更された skills
- `.claude/skills/adopt-sidekick-update/SKILL.md`
- `.claude/skills/setup/SKILL.md`
- `.claude/skills/release/references/release-format-spec.md`

## [0.7.3] - 2026-05-05 ⚠️ [CRITICAL]

### Added
- ADR-0014: sidekick の ADR は下流 PJ に配布しない方針

### Changed
- `/adopt-sidekick-update`: ADR (`docs/decisions/`) を取り込み対象から除外（ADR-0014）。下流 PJ の `docs/decisions/` は下流自身の領域として完全分離。`[ADR]` カテゴリは「参考表示のみ」に縮退

### Fixed
- `/adopt-sidekick-update`: 下流 PJ の `docs/decisions/README.md` が blind overwrite され ADR 索引が消失する Critical bug（ADR-0014 で恒久対応）

### Breaking Changes
- `/adopt-sidekick-update` が下流 PJ の `docs/decisions/` を取り込まなくなる
- 既存下流 PJ で取り込まれた sidekick ADR ファイル（0007/0008/0009/0010/0012/0013 等）は手動削除が必要
- 上書きされた `docs/decisions/README.md` は下流独自内容に手動復元が必要

### 変更された ADR
- `docs/decisions/0014-sidekick-adr-not-distributed.md` (新規)
- `docs/decisions/README.md` (索引更新)

### 変更された skills
- `.claude/skills/adopt-sidekick-update/SKILL.md`

## [0.7.2] - 2026-05-04

### Fixed

- `/adopt-sidekick-update` Step 6.4a の Project Configuration 新フィールド検出が silent に失敗する事象を修正。bash のパイプ経由 `while read` ループはサブシェル化により早期終了することがあるため、heredoc (`done <<< "$VAR"`) 形式に統一
  - 失敗モード: 検出ゼロでスキップ（エラーなし、非破壊的）
  - 影響: 新フィールド (NOTION_JUDGMENT_SYNC 等) が下流 PJ の CLAUDE.md に追加されない
  - 修正: Step 6.4a のロジックを heredoc + bash 配列に変更。Gotchas に「while read は heredoc で」の注意を追加

## [0.7.1] - 2026-05-04

### Fixed

`/adopt-sidekick-update` の dogfood で発見した 6 件の bug を修正。下流 PJ が新リリースを取り込む際の安全性を向上。

- **CLAUDE.md / README\* / .gitignore の盲目的上書きを停止** (Step 6): PJ-protected files は専用の migration step (Step 6.4) で扱う。Project Configuration 値や PJ 独自 README が消える事故を防ぐ
- **SIDEKICK_VERSION 抽出 regex をシングル/ダブルクォート両対応に** (Step 0): 書式揺れに耐性を持たせる
- **`[PJ migration]` カテゴリのデフォルトを `[n]個別判断` に** (Step 4): PJ 固有内容を含むカテゴリは安全側に倒す
- **CLAUDE.md migration step 新設** (Step 6.4): (a) Project Configuration の新フィールドを既存値を壊さず append (b) brain `@import` 接続の確認と案内 (c) README\* / .gitignore は差分案内のみ
- **タグ参照化** (Step 5/6/6.5): `git show ${LATEST}:<path>` (リリース時点固定) に変更し、post-release commit との drift を回避

### Changed

- カテゴリを 5 種に再編成: `[ADR]` / `[rules]` / `[skills]` / `[brain]` / `[PJ migration]`

## [0.7.0] - 2026-05-02

### Added
- **brain 3 層構造**（ADR-0013）: 思考OS の格納先を「業界共通 (L0) / 個人 (L1) / PJ 固有 (L2)」の 3 スコープに分離。各層は `@import` でチェーン化（L2 → L1 → L0）
  - 新規 `brain/thinking.md` (L0 マスター、OSS 配布物として業界共通の判断軸を保持)
  - 新規 `.claude/brain/thinking.md` (L2 テンプレ、PJ 固有判断軸の置き場)
  - CLAUDE.md §1 を brain への参照に縮約。PJ 固有判断軸は L2 へ
- **個人情報・固有名詞の混入防止ルール**（HARD グレード、新規 `.claude/rules/pii-prevention.md`）: Notion ID/URL・内部 URL・接続情報のパターンと `scan_pii` 関数を提供。`/record-decision` `/close-chat` でセルフレビューを自動実行
- **Notion 判断ログ同期**（ADR-0012、opt-in）: 設計判断・方針判断を Notion 判断ログDB に蓄積する機能。`NOTION_JUDGMENT_SYNC` 独立フラグで `NOTION_ENABLED` と疎結合に制御
- ADR-0010: 思考OS の 2 層構造と配布・還流メカニズム（一部 Superseded by ADR-0013）
- `/setup` Step 4.5: brain 3 層配置パターン（物理コピー / L1 import のみ / 3 層 chain 推奨）の選択肢
- `/adopt-sidekick-update` Step 6.5: ホーム L0 (`~/.claude/ccs/brain/thinking.md`) の自動展開 + L1 案内
- `/record-decision` Step 5: ADR ドラフト完成後の PII セルフレビュー
- `/close-chat` Step 5.6: 公開ファイル変更時の PII セルフレビュー
- `/close-chat` Step 6.5: Notion 判断ログDB 同期（`NOTION_JUDGMENT_SYNC=true` の場合のみ）
- `CLAUDE.md` Project Configuration に `NOTION_JUDGMENT_SYNC` / `NOTION_JUDGMENT_DB_URL` を追加（デフォルト false）
- `.claude/rules/task-management.md` に「判断ログ同期」セクション（Notion 判断ログDB スキーマ定義含む）

### Changed
- `.claude/rules/code-quality.md`: 抽象的判断原則の参照先を thinking.md → brain L0 に更新
- `.claude/rules/knowledge-map.md`: 格納レイヤー表に L0/L1/L2 を反映、判断フロー・昇格ルール（PJ 内 → L2、別 PJ 観測 → L1、業界共通 → L0）を更新
- 還流タグを 3 層化: `[ベース昇格]` `[思考OS還流]` `[固有]` → `[L0候補]` `[L1候補]` `[L2固有]`（`/close-chat` `/weekly-inventory` の references 含む）
- README / README.ja の Quick Start 例を `--private --clone` 付きに更新（個人開発のフォーク手順を改善）

### Renamed
- `.claude/rules/thinking.md` → `brain/thinking.md`（思考OS を L0 として独立。`@import` で参照）

## [0.6.0] - 2026-04-18

### Added
- `/release` スキル新規（リリース発信側。温度感判定 + 機械的変更リスト生成 + CHANGELOG bump + tag + GitHub Release 作成）
- `/adopt-sidekick-update` スキル新規（下流 PJ の取り込み対話、カテゴリ一括 UX、スキップ永久/後回し記録）
- ADR-0009: リリース取り込み設計（温度感・思想漏洩防止・スキップ制御。P1+P2+P3 全実装）
- `/inventory` に Release severity 判定追加（Critical のみ強調、Standard/Enhancement は 1行サマリ）
- `/inventory` が Critical 検知時に auto-memory フラグファイル作成
- `/weekly-inventory` Step 0.5 追加（sidekick 未取込更新の棚卸し、全 severity、経過日数警告）
- `/setup` に ccs remote 自動追加ステップ
- `session-start.sh` に `[6/6] Critical sidekick update` セクション（未取込 Critical 警告の継続表示）
- `/adopt-sidekick-update` の Step 6 で Critical フラグをクリア

### Changed
- **`/weekly-review` → `/weekly-inventory` へ rename**（実態は棚卸し系のため `/inventory` との命名整合）
- CHANGELOG intro にリリース温度感セクション追加
- 関連ドキュメントの `/weekly-review` 参照を更新

## [0.5.0] - 2026-04-18

### Added
- `/discover` スキル（アイデア → 要件定義 → タスク分解の対話型スキル）
- `/discover` に仕様セルフレビューチェックポイント（Step 4 / Step 5 前の thinking.md §2 準拠チェック）
- `/close-chat` に CHANGELOG 整合性チェックステップ（Step 5.5）
- `/weekly-review` にドキュメント整合性チェック（ADR index・CHANGELOG drift・README stale 検出）
- `CLAUDE.md` Project Configuration に `SIDEKICK_VERSION` を追加
- ADR-0007（thinking-os positioning）、ADR-0008（MEMORY.md 廃止・auto-memory 一本化）
- 下流 PJ 向け移行ガイド `docs/migrations/memory-md-to-auto-memory.md`

### Changed
- README に `/discover` を反映、スキル総数 14 → 15、スキル間連携フロー図追加
- README / README.ja のスキル記述を「project-root MEMORY.md」→「auto-memory」に書き換え
- `/close-chat` / `/inventory` / `/setup` の MEMORY.md 参照を auto-memory 前提に統一
- `.claude/rules/documentation.md` / `knowledge-map.md` を auto-memory 一本化前提に書き換え
- CLAUDE.md H13 / ゲート3 を auto-memory 前提に明文化
- `.gitattributes` で全テキストファイルを LF 強制
- thinking.md を「入れ替え可能な思考OS」として位置づけ（ADR-0007）
- settings.json の hooks を公式 JSON フォーマットに移行

### Removed
- `.claude/templates/MEMORY.md`（ADR-0008 により廃止）
- `.gitignore` の `/MEMORY.md` エントリ（配置対象外になったため）

### Fixed
- hook の `echo` を `printf` に修正（Windows パスで全ガードが無効化されるバグ）
- SVG 内の "14 Skills" を "15 Skills" に修正

### Breaking Changes
- **下流 PJ**: project-root `/MEMORY.md` の手動移行が必要。`docs/migrations/memory-md-to-auto-memory.md` を参照

## [0.4.1] - 2026-04-09

### Changed
- settings.json の permissions.allow を `Bash(*)` に一本化（ADR-0002 ブラックリスト方式の完全準拠）
- guard-db-operation.sh: PRD DB 検出時に exit 0（警告）→ exit 2（ブロック）に強化
- permissions.deny に `prisma db push`（npx なし版）、`git push --force-with-lease` を追加
- README（EN/JA）の防御モデル説明を4層構造（deny / guard / HARD / auto）に更新

## [0.4.0] - 2026-04-09

### Added
- `/setup` に既存PJモードを追加（CLAUDE.md が既にある場合の非侵襲的セットアップ）
- `.claude/templates/` ディレクトリ（MEMORY.md, CLAUDE.local.md, GitHub テンプレート）
- `.claude/docs/` ディレクトリ（毎セッション読み込まない開発者リファレンス）
- `/auto-implement` に推奨ユースケースセクション（テスト追加から始める段階的導入ガイド）
- ADR-0005: 下流統合設計原則（.claude/ 封じ込め、opt-in 配置、既存PJ非侵襲）

### Changed
- バージョン管理を VERSION ファイル → git tag + GitHub Releases に移行
- `/inventory` のバージョンチェックが GitHub Releases API を使用
- `/setup` の .gitignore 追記がファイル配置と連動（配置しなかったファイルのパターンは追記しない）
- `skill-agent-design.md` を `rules/` → `.claude/docs/` に移動（コンテキスト常駐の解消）
- `mcp-recommendations.md` を `rules/` → `skills/setup/references/` に移動（/setup 時のみ参照）
- `MEMORY.md.example` → `.claude/templates/MEMORY.md` に移動
- `CLAUDE.local.md.example` → `.claude/templates/CLAUDE.local.md` に移動
- `.github/` テンプレートの下流向けコピーを `.claude/templates/github/` に分離
- `.gitignore` のコメント構造を整理（コア/配置依存/PJ固有の区分）

### Removed
- ルートの `VERSION` ファイル（git tag に移行）

## [0.3.0] - 2026-04-08

### Added
- `/review-design` スキル（UI/UX一貫性・デザインシステム・a11y）
- `/review-spec` スキル（API契約・仕様書乖離・破壊的変更）
- `/review` の動的スコープ判定で design/spec を自動選択
- Stop hook（設計判断のADR記録漏れを自動検出。再発火防止付き）
- guard-bash.sh Guard 8: PRマージ時のベースブランチ動的判定
- settings.json に deny[] セクション（禁止事項の可視化）
- テスト実行最適化ルール（ローカル=スコープ限定、main=フル）
- `/setup` Step 4: オーナー情報ヒアリング（テンプレ選択肢 + 全スキップ可）

### Changed
- `/weekly-review` に外部情報収集・hooks実績分析を統合（旧scout-process機能）
- thinking.md Step 4: 一貫性チェック対象を明示化（CLAUDE.md, thinking.md, ADR, feedback）

### Removed
- `/scout-process`（weekly-reviewに統合）
- `/scout-product`（テンプレートのまま使われにくいため削除）
- `/sync-to-notion`（Notion依存解消方針に伴い削除）

## [0.2.0] - 2026-04-07

### Added
- 外部タスク管理連携プロトコル（CLAUDE.md §9 + `.claude/rules/` で設定）
  - Tasks DB 同期、Sourceタグ、即時投入ルール
- ADR（Architecture Decision Records）体制
  - `docs/decisions/` + `/record-decision` スキル
  - ADR-0001〜0004: OSS配信、ブラックリスト方式、Slack連携、コンテキスト集約
- 知識の格納マップ（`.claude/rules/knowledge-map.md`）
- `/weekly-review` スキル（定期棚卸し）
- `/close-chat` に知識還流チェック（Step 2.5）を追加
- VERSION + CHANGELOG によるリリース管理

## [0.1.0] - 2026-04-06

### Added
- AI伴走開発ベーステンプレートの初版
  - CLAUDE.md: HARD/SOFT/GUIDE ルール体系
  - thinking.md: 判断基盤と行動プロトコル
  - hooks: guard-bash, guard-commit-message, guard-db-operation, guard-protected-branch-edit
  - skills: close-chat, news, record-decision, review (code/ops/test), setup, sync-to-notion
  - Worktree 運用プロトコル
  - Git Strategy（ブランチ戦略、PR作成ゲート、Merge Strategy）
- 運用プロジェクト実績からのバックポート
- public リポジトリでの固有名詞除外ルール
