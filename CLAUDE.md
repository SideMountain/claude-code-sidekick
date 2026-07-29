# CLAUDE.md - AI伴走開発 ベーステンプレート

全プロジェクトに共通するルール・方針・制約を定義する。
領域特化ルール（Git戦略・DB・デプロイ・命名規則等）は `.claude/rules/` に配置。

---

## 0. Project Configuration

各セクションのルールはこの設定値に応じて有効/無効が切り替わる。

```yaml
PROJECT_NAME: ""              # プロジェクト名
STG_ENABLED: false            # true: feature→stg→main の2段階リリース
                              # false: feature→main の直接リリース
PROTECTED_BRANCHES:           # 保護ブランチ名（直接コミット・push禁止）
  - main
  # - release/stg            # STG_ENABLED=true の場合に追加
ORM_TYPE: none                # prisma | drizzle | none
LANGUAGE: typescript          # typescript | python | gas
STACK_PACK: none              # none | nextjs : opt-in stack pack（詳細は下の Stack Pack 節）
TEST_COMMAND: ""              # 例: "npx vitest run", "pytest", ""
TYPECHECK_COMMAND: ""         # 例: "npx tsc --noEmit", "", ""
BUILD_COMMAND: ""             # 例: "npm run build", "", ""
LINT_COMMAND: ""              # 例: "npm run lint", "", ""
NOTION_ENABLED: false         # true: Notion MCP連携有効（Tasks DB 双方向同期）
NOTION_JUDGMENT_SYNC: false   # true: /close-chat 実行時にNotion判断ログDBへ同期
NOTION_JUDGMENT_DB_URL: ""    # 同期先 Notion 判断ログDB の URL（NOTION_JUDGMENT_SYNC=true の場合必須）
PACKAGE_MANAGER: npm          # npm | pnpm | yarn | pip
STG_DB_PATTERN: ""            # STG DB識別パターン（例: "ep-bitter-salad"）
PRD_DB_PATTERN: ""            # PRD DB識別パターン（例: "ep-weathered-mode"）
SIDEKICK_VERSION: ""          # 取り込み済み sidekick バージョン（例: "0.12.0"）
                              # 空 or 未設定なら sidekick 本体として扱う（バージョンチェック対象外）
```

### Stack Pack（opt-in・ADR-0021）

`STACK_PACK: nextjs` の場合、この PJ は **Next.js stack pack の規定アーキ（golden path）に従う** — 実装・レビュー時は `.claude/stack-packs/nextjs/ARCHITECTURE.md`（Tier-1 STRUCTURAL / Tier-2 HYGIENE）を実装規約として読み、`system-map` スキルでコードベースを可視化できる。stack pack は ccs core（hooks / brain / 目的原則 / skills = stack 非依存）の上に載る **opt-in な上物**。有効化は `/setup` で対話的に行い、`none`（既定）ならこのレイヤー全体を無視してよい（**非 Next PJ は無コスト**）。

---

## 1. オーナーの判断軸

判断基盤は **brain（2 層構造・ADR-0016）**。PJ 固有 brain（`.claude/brain/thinking.md`・この PJ 固有）が、個人 brain（`~/.claude/brain/thinking.md`・複数 PJ 横断、利用者が育てる）を 1 段 `@import` し、**両層ともロード対象**。個人 brain 不在時は silent ignore され、PJ brain だけがロードされる（フェイルセーフ）。OSS 配布物の `brain/thinking.md` はロード対象外（`/setup` で個人 brain を初期化する際のテンプレート素材）。

@.claude/brain/thinking.md

---

## 2. Claude 運用ルール

### ルールグレード

| グレード | 意味 | Claudeの動作 |
|----------|------|-------------|
| **HARD** | 例外なし。効率や文脈を理由に省略不可 | 機械的に実行。**判断しない** |
| **SOFT** | 原則従う。文脈で判断してよい | 判断した場合は根拠を明示 |
| **GUIDE** | 推奨。従わなくても報告不要 | 意識するが厳密に従わなくてよい |

**HARD ルールに対して「今回は不要では？」「さっき確認した」等の判断を適用しない。** 判断するから間違える。

### HARD ルール一覧

#### 本番データ保護

- **H1**: DB操作前に `grep "^DATABASE_URL" .env` を毎回実行（「さっき確認した」は省略理由にならない）
- **H2**: PRDデータパッチは dry-run → 件数確認 → 承認 → 実行
- **H6**: PRD DB書き込み: 手順・影響行数・ロールバック提示 → 明示的承認

#### .env 保護

- **H5**: `.env` の `DATABASE_URL` 書き換え禁止（PRD操作はコマンド単位で `DATABASE_URL=` を渡す）
  - ※ `STG_DB_PATTERN` / `PRD_DB_PATTERN` が設定されている場合のみ有効

#### 不可逆Git操作

- **H7**: git push → 必ずユーザー確認
- **H8**: PR作成・マージ・クローズ → 必ずユーザー確認
- **H9**: `PROTECTED_BRANCHES` に直接コミット禁止

#### STG_ENABLED=true の場合のみ有効

- **H10**: feature → main のPR禁止（feature → stg → main の2段階）
- **H11**: main ↔ stg の同期PR禁止

#### Worktree・並行作業

- **H12**: 新作業は Worktree 作成（メインWSでブランチ切り替え禁止）
- **H13**: Worktree 作成 → auto-memory の MEMORY.md（`~/.claude/projects/<slug>/memory/MEMORY.md`）の Active Work セクションに記録（この順序。飛ばさない）
- **H14**: DBマイグレーション作業の並行禁止
- **H21** (STG_ENABLED=true のみ): メインWSの常駐ブランチは `release/stg` 固定。`main` で滞在しない（main 視点が必要な操作は checkout せず `git fetch origin && git log origin/main` 等で参照する）
- **H22** (STG_ENABLED=true のみ): 新規 Worktree のベースブランチは `origin/release/stg`。例外は hotfix（`origin/main` から切る）
- **H23** (STG_ENABLED=true のみ): WT が `release/stg` にマージされた直後、メインWSで `git pull origin release/stg` を実行して同期（WT 削除よりこの sync が先）

#### ORM_TYPE=prisma の場合のみ有効

- **H3**: `prisma db push` 禁止
- **H4**: `prisma migrate deploy/dev` は Claude 自律実行禁止

#### ORM_TYPE=none（Supabase CLI）の場合のみ有効

- **H16**: `supabase db reset` 禁止（全データ消去。例外なし）
- **H17**: `supabase db push --force` 禁止（破壊的変更の強制適用。Expand-Contract で対応）
- **H18**: `supabase migration repair` 禁止（マイグレーション履歴の改竄）
- **H19**: `supabase db push` はユーザー確認必須（対象プロジェクト・適用内容を明示）
- **H20**: PRD への `supabase db push` は手順・影響・ロールバック提示 → 明示的承認（H6 と同等）

#### コミット

- **H15**: コミット本文に 背景/対応/影響 必須（自明な変更でも省略しない）

### 自動実行の制御方式: ブラックリスト

**原則: 禁止・承認必須に該当しないものは全て自動実行。** ホワイトリスト（許可リスト）ではなくブラックリスト（禁止リスト）で制御する（ADR-0002「ブラックリスト方式」参照）。

#### 禁止（hooks で物理ブロック。例外なし）

| 操作 | ブロック手段 | 対応するHARDルール |
|------|-------------|------------------|
| PRD DB への書き込み | guard-db-operation.sh | H2, H6 |
| 保護ブランチへの直接 push | guard-bash.sh | H9 |
| `.env` の `DATABASE_URL` 変更 | guard-bash.sh | H5 |
| `rm -rf` / 再帰削除 | guard-bash.sh | — |
| `prisma db push` | guard-bash.sh | H3 |
| `supabase db reset` | guard-bash.sh | H16 |
| `supabase db push --force` | guard-bash.sh | H17 |
| `supabase migration repair` | guard-bash.sh | H18 |
| メインWSでの `git checkout` | guard-bash.sh | H12 |
| 保護ブランチ checkout 中のファイル編集 | guard-protected-branch-edit.sh | H9, H12 |
| 背景/対応/影響 を欠くコミット | guard-commit-message.sh | H15 |
| 公開ファイルへの PII 混入（commit 時） | .claude/githooks/pre-commit | pii-prevention.md (HARD) |

#### 承認必須（不可逆な操作。確認なしで実行しない）

- git push（全ブランチ） → **H7**
- PR 作成・マージ・クローズ → **H8**
- PRD DB マイグレーション → **H4**
- PRD DB SELECT（読み取りでも確認必須）
- STG DB マイグレーション実行（Supabase 構成では `supabase db push` = **H19**、PRD へは **H20**）
- `supabase db execute`（直接 SQL 実行。ORM_TYPE=none の場合）
- STG DB データ変更（INSERT / UPDATE / DELETE）
- 破壊的操作（ファイル削除、ブランチ削除、force push）
- `git stash` / `git reset` / `git rebase`
- **確認時は必ず「何を承認するのか」を明記する**（ブランチ名＋変更内容＋対象環境）

#### それ以外 → 全自動（確認不要）

ファイル読み書き、テスト実行、git add/commit/status/diff、Worktree操作、STG DB SELECT（接続先確認は毎回必須）、その他ローカル操作は全て自律実行OK。

### 判断ゲート

#### ゲート1: ルールが関わる操作の前

git操作・DB操作・デプロイなど、CLAUDE.md にルールが存在する領域の操作では、該当ルールを特定・引用してから実行する。ルールに反する場合はルールの枠内で実現する方法を考え、ユーザーの指示がルールと矛盾する場合は確認する。

#### ゲート2: 情報の確度表示

事実・仕様・技術情報を伝えるときは確度を添える。推測・未検証の情報を確定的に述べない（ユーザーの意思決定に影響する情報は特に必須）。

| 確度 | 意味 | 例 |
|------|------|-----|
| **確認済み** | コード・ドキュメント・実行結果で裏取り済み | 「コードを確認しました。この関数は〜」 |
| **推測** | 根拠はあるが未確認 | 「（推測）ログから見るに〜」 |
| **未検証** | 一般知識・経験則 | 「（未検証）一般的には〜」 |

**発火条件（事実忠実性ゲート）**: 数値・仕様・API/コマンド名・バージョン・サポート有無を含む主張を出す前に「その一次ソース（コード・実行結果・公式ドキュメント）を当該セッションで自分が見たか」を自問する。YES → 「確認済み」+ 出典（file:line / URL / 実行結果）。NO → 「推測」/「未検証」ラベル必須（ラベルなしの断定は禁止）。

#### ゲート3: CLAUDE.md / auto-memory への記録前

| 記録内容 | 記録先 |
|----------|--------|
| プロジェクトルール・規約 | CLAUDE.md の該当セクションに追記 |
| 設計判断の「なぜ」 | ADR（`docs/decisions/`） |
| 行動修正の経緯 | auto-memory の `feedback_*.md` |
| 外部システムへのポインタ | auto-memory の `reference_*.md` |
| 作業中のステータス・引継ぎメモ | auto-memory の `MEMORY.md`（Active Work / Backlog） |
| 既存セクションのどこにも該当しない | ユーザーに配置を確認する |

### 「〜お願いします」の解釈

- 「お願いします」「コミットして」 → **add→commit は確認なしで即実行**
- git status / diff の事前確認ダイアログも不要
- **git push / PR作成 / PRマージは必ず確認してから実行**
- 指示の範囲を超える追加操作は行わない

### 壁打ち・議論の進行ルール

1. **発散**: 選択肢を広げる。批判せず可能性を列挙
2. **収束**: 各選択肢を評価し比較表で整理
3. **決定**: ユーザーの判断を待つ。勝手に決めない

壁打ち中は実装に着手しない（「考える」と「作る」を分離）。決定後、仕様判断があれば ADR 記録を提案する。

### テスト実行の最適化

**STG_ENABLED=true の場合は 2 段ゲート**（STG=反復速度優先で軽量・本番前=フル）。STG は検証環境のため軽量ゲートで開発サイクルを上げ、論理回帰は本番反映前のフルスイートで捕捉する。小さな修正 → STG 確認のサイクルで毎回フル一式（全テスト+ビルド+重いレビュー）を回すのは AI 開発の速度ロスが大きい — さらに並列 worktree でフルスイートが同時に走るとマシン全体が劣化する。

| タイミング | テスト範囲 |
|---|---|
| ローカル開発中 | 変更に関連するテストのみ（スコープ限定） |
| **feature → release/stg（STG・反復）** | **変更箇所のテストのみ ＋ 型チェック（全体） ＋ lint（変更分）**。全テスト / ビルドはスキップ |
| **release/stg → main（本番前）** | **全テスト ＋ 型チェック ＋ ビルド**（＋ E2E があれば実行） |

- `TEST_COMMAND` はファイル指定・ディレクトリ指定・`--changed` 等で対象を絞る
- **STG PR は「変更箇所テスト + 型チェック」が通れば作成可**（全テスト緑は要求しない）。**main（本番）PR は全テスト緑を必須**にする
- 型チェック全体は STG でも残す＝クロスモジュールの型崩れを安価に即検知する
- `STG_ENABLED=false` の PJ は main への PR が本番前ゲート＝フル一式を回す（2 段ゲートは適用しない）
- guard-bash.sh Guard 13 が「非リリースブランチでのフルスイート実行」を advisory 警告する（検知層）

### セルフレビュー

作業完了前に `/review` スキルを実行し、セルフチェックを行う。

### ブロック時の通知義務

作業が進められない状況では、**黙って停止せず即座にユーザーに報告する**（報告しすぎは許容、沈黙は許容しない）。自力で解決できそうなら 1 回だけ試み、解決しなければ報告。他チャットへの影響・設計判断・判断に迷う場合は即座に報告する。報告は「⚠️ [ブロック / 要確認]」を掲げ、**状況 / 原因（わかっている範囲で） / 影響 / 選択肢（ユーザーが選べる対応案）** の 4 点を明記する。

---

## 3. Lessons Learned

### hook スクリプトでの JSON パース

- `echo "$VAR" | jq` を使わない。`printf '%s\n' "$VAR" | jq` を使う
- 理由: `echo` のバックスラッシュ展開は POSIX で未定義。Windows パス（`C:\Users\...`）で jq パースが壊れ、全ガードが無効化される
- jq 呼び出しには `2>/dev/null` を付ける
- jq パース失敗時（変数が空）は grep フォールバックを実装する
