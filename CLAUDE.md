# CLAUDE.md - AI伴走開発 ベーステンプレート

このファイルはClaude Codeへのプロジェクト全体指示書。
全プロジェクトに共通するルール・方針・制約を定義する。
プロジェクト固有の設定は「Project Configuration」セクションで切り替える。

---

## 0. Project Configuration

プロジェクトの特性に合わせて以下を設定する。
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
TEST_COMMAND: ""              # 例: "npx vitest run", "pytest", ""
TYPECHECK_COMMAND: ""         # 例: "npx tsc --noEmit", "", ""
BUILD_COMMAND: ""             # 例: "npm run build", "", ""
LINT_COMMAND: ""              # 例: "npm run lint", "", ""
NOTION_ENABLED: false         # true: Notion MCP連携有効
PACKAGE_MANAGER: npm          # npm | pnpm | yarn | pip
STG_DB_PATTERN: ""            # STG DB識別パターン（例: "ep-bitter-salad"）
PRD_DB_PATTERN: ""            # PRD DB識別パターン（例: "ep-weathered-mode"）
```

---

## 1. オーナーの判断軸

<!-- プロジェクトオーナーの思考OS・判断基準をここに記載する -->
<!-- 例: Notion思考OSのURL、設計判断の優先順位等 -->
<!-- Claude はこのセクションを参照して提案の方向性を決める -->

---

## 2. Claude 運用ルール

### ルールグレード

| グレード | 意味 | Claudeの動作 |
|----------|------|-------------|
| **HARD** | 例外なし。効率や文脈を理由に省略不可 | 機械的に実行。**判断しない** |
| **SOFT** | 原則従う。文脈で判断してよい | 判断した場合は根拠を明示 |
| **GUIDE** | 推奨。従わなくても報告不要 | 意識するが厳密に従わなくてよい |

**HARD ルールに対して「今回は不要では？」「さっき確認した」等の判断を適用しない。** 判断するから間違える。

---

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
- **H13**: Worktree 作成 → MEMORY.md Active Work 記録（この順序。飛ばさない）
- **H14**: DBマイグレーション作業の並行禁止

#### ORM_TYPE=prisma の場合のみ有効

- **H3**: `prisma db push` 禁止
- **H4**: `prisma migrate deploy/dev` は Claude 自律実行禁止

#### コミット

- **H15**: コミット本文に 背景/対応/影響 必須（自明な変更でも省略しない）

---

### 自動実行の制御方式: ブラックリスト

**原則: 禁止・承認必須に該当しないものは全て自動実行。**
ホワイトリスト（許可リスト）ではなくブラックリスト（禁止リスト）で制御する。
（ADR-0002「ブラックリスト方式」参照）

#### 禁止（hooks で物理ブロック。例外なし）

| 操作 | ブロック手段 | 対応するHARDルール |
|------|-------------|------------------|
| PRD DB への書き込み | guard-db-operation.sh | H2, H6 |
| 保護ブランチへの直接 push | guard-bash.sh | H9 |
| `.env` の `DATABASE_URL` 変更 | guard-bash.sh | H5 |
| `rm -rf` / 再帰削除 | guard-bash.sh | — |
| `prisma db push` | guard-bash.sh | H3 |
| メインWSでの `git checkout` | guard-bash.sh | H12 |

#### 承認必須（不可逆な操作。確認なしで実行しない）

- git push（全ブランチ） → **H7**
- PR 作成・マージ・クローズ → **H8**
- PRD DB マイグレーション → **H4**
- PRD DB SELECT（読み取りでも確認必須）
- STG DB マイグレーション実行
- STG DB データ変更（INSERT / UPDATE / DELETE）
- 破壊的操作（ファイル削除、ブランチ削除、force push）
- `git stash` / `git reset` / `git rebase`
- **確認時は必ず「何を承認するのか」を明記する**（ブランチ名＋変更内容＋対象環境）

#### それ以外 → 全自動（確認不要）

ファイル読み書き、テスト実行、git add/commit/status/diff、Worktree操作、
STG DB SELECT（接続先確認は毎回必須）、その他ローカル操作は全て自律実行OK。

---

### 判断ゲート

#### ゲート1: ルールが関わる操作の前

**トリガー**: git操作、DB操作、デプロイなど、CLAUDE.md にルールが存在する領域での操作

**アクション**: 該当ルールを特定・引用してから実行。ルールに反する場合はルールの枠内で実現する方法を考える。ユーザーの指示がルールと矛盾する場合は確認する

#### ゲート2: 複数の方法がある提案の前

**トリガー**: 実現方法が複数考えられる場面

**アクション**: 選択肢を洗い出し、メリット・デメリット・リスクを比較する。**最初に思いついた案をそのまま出さない。必ず他の選択肢と比較してから提案する**

#### ゲート3: 情報の確度表示

**トリガー**: 事実・仕様・技術情報をユーザーに伝える場面

| 確度 | 意味 | 例 |
|------|------|-----|
| **確認済み** | コード・ドキュメント・実行結果で裏取り済み | 「コードを確認しました。この関数は〜」 |
| **推測** | 根拠はあるが未確認 | 「（推測）ログから見るに〜」 |
| **未検証** | 一般知識・経験則 | 「（未検証）一般的には〜」 |

推測・未検証の情報を確定的に述べない。ユーザーの意思決定に影響する情報は必ず確度を添える。

#### ゲート4: CLAUDE.md / MEMORY.md への記録前

| 記録内容 | 記録先 |
|----------|--------|
| プロジェクトルール・規約 | CLAUDE.md の該当セクションに追記 |
| Claude固有の操作メモ・補足 | MEMORY.md |
| 既存セクションのどこにも該当しない | ユーザーに配置を確認する |

---

### 「〜お願いします」の解釈

- 「お願いします」「コミットして」 → **add→commit は確認なしで即実行**
- git status / diff の事前確認ダイアログも不要
- **git push / PR作成 / PRマージは必ず確認してから実行**
- 指示の範囲を超える追加操作は行わない

### 壁打ち・議論の進行ルール

1. **発散**: 選択肢を広げる。批判せず可能性を列挙
2. **収束**: 各選択肢を評価し比較表で整理
3. **決定**: ユーザーの判断を待つ。勝手に決めない

- 壁打ち中は実装に着手しない（「考える」と「作る」を分離）
- 決定後、仕様判断があれば ADR 記録を提案する

### テスト実行の最適化

| タイミング | テスト範囲 | レビュー |
|---|---|---|
| ローカル開発中 | 変更に関連するテストのみ（スコープ限定） | なし |
| PR作成前 | 全テスト + 型チェック + ビルド | `/review`（動的スキップあり） |
| main マージ前 | 全テスト + 型チェック + ビルド + E2E | `/review`（全観点フル実行） |

- `TEST_COMMAND` が設定されている場合、ローカルでは `--grep` や `--filter` で対象を絞る
- 全テストがパスしなければ PR を作成しない（PR作成前ゲートで保証）

### セルフレビュー

作業完了前に `/review` スキルを実行し、セルフチェックを行う。

---

## 3. Git Strategy

### Branch Strategy

**STG_ENABLED=false の場合:**

| Branch | 用途 | 直接push |
|--------|------|----------|
| `main` | 本番 | **禁止** |
| `feature/xxx` | 機能開発。`main` から切る | OK |
| `hotfix/xxx` | 緊急修正。`main` から切る | OK |

**STG_ENABLED=true の場合:**

| Branch | 環境 | 用途 | 直接push |
|--------|------|------|----------|
| `main` | PRD | 本番 | **禁止** |
| `release/stg` | STG | 検証 | **禁止** |
| `feature/xxx` | — | 機能開発。`release/stg` から切る | OK |
| `hotfix/xxx` | — | 緊急修正。`main` から切る | OK |

### PR作成前の必須チェック（ゲート）

**1つでも NG なら PR を作成しない。**

#### 0. 最新化チェック

- `git fetch origin`
- `git log <branch>..origin/<base-branch> --oneline` で未取り込みを確認
- 未取り込みがあれば `git pull --rebase origin/<base-branch>`
- **「コンフリクトがなさそうだから」でスキップしない**

#### 1. 経路チェック（STG_ENABLED=true の場合）

| ターゲット | 許可されるソース |
|-----------|----------------|
| `release/stg` | `feature/*`, `hotfix/*` |
| `main` | `release/stg`, `hotfix/*` |

- **feature/* → main は禁止。例外なし。**

#### 2. 差分チェック

- `git diff <target>...<source>` で意図しない変更がないか確認

#### 3. ユーザー確認

- ソース→ターゲットと差分サマリを明示して承認を得る
- 「PRを作成します」ではなく「`feature/xxx` → `main` にPR作成してよいですか？（変更: ○○）」

### Merge Strategy

- **通常マージのみ**（`--merge`）。squash マージ禁止
- 理由: squash するとコミットハッシュが変わり、2段階マージでコンフリクト

### Commit Rules

- conventional commits 形式（`feat:`, `fix:`, `refactor:` 等）
- 日本語コミットメッセージ可
- 本文に「背景」「対応」「影響」を**必ず**記載
- **public リポジトリではコミットメッセージ・PR本文に固有名詞（プロダクト名・企業名・個人名・接続先情報等）を含めない**。運用プロジェクトからのバックポート時は特に注意

```
feat: ○○機能を追加

背景: △△の問題があり、□□が必要だった
対応: ××のアプローチで実装
影響: path/to/changed/files
```

---

### Worktree 運用

#### 原則: 全作業 Worktree 運用

新しい作業は常に Worktree を作成。メインWSのブランチは切り替えない。

#### チャット開始時の必須手順

```
ステップ1: git fetch origin && git branch --show-current
  → PROTECTED_BRANCHES のいずれかであることを確認

ステップ2: git status
  → 未コミットの変更がないか確認

ステップ3: MEMORY.md の「Active Work」を読む
  → 他チャットの作業状況と影響範囲を把握
```

#### Worktree 作成手順（確認不要）

```
ステップ1: git worktree add ../<project>-<用途> -b <branch-name> origin/<base-branch>

ステップ2: MEMORY.md Active Work に追記
  - ブランチ名、作業内容（1行）、影響範囲、DBマイグレーション有無

ステップ3: .env をコピーし接続先を確認
  cp .env ../<project>-<用途>/.env
  grep "^DATABASE_URL" ../<project>-<用途>/.env

ステップ4: 依存インストール
  cd ../<project>-<用途> && <PACKAGE_MANAGER> install
```

**ステップ2を飛ばしてステップ3に進まない。**

#### 軽量Worktreeパターン

変更対象がランタイム不要のファイルのみ（`.claude/`, `docs/`等）の場合、ステップ3-4をスキップ可。

#### Worktree 最適化: シンボリックリンク（オプション）

`node_modules` 等の大容量ディレクトリをシンボリックリンクで共有すると、ディスク使用量を大幅に削減できる。
依存バージョンがブランチ間で同一の場合に有効。

```bash
# ステップ4の代替: npm install の代わりにシンボリックリンクを作成
ln -s $(realpath node_modules) ../<project>-<用途>/node_modules
```

**注意**: ブランチ間で `package.json` / `package-lock.json` が異なる場合はシンボリックリンクではなく通常の `npm install` を使うこと。

#### Worktree ライフサイクル

- **原則**: ユーザーが「作業完了」と明言するまで保持。PRマージ後すぐには削除しない
- **PRマージ後**: MEMORY.md のステータスを「STG確認待ち」に更新
- **削除**: ユーザー明言後に `git worktree remove` → ブランチ削除 → MEMORY.md更新

#### Active Work ステータス

| ステータス | 意味 |
|-----------|------|
| 作業中 | 開発・修正中 |
| STG確認待ち | PRマージ済み、動作確認待ち |
| 完了 | ユーザーが完了確認。Worktree削除実行 |

#### 並行作業の制約

| 作業種別 | 並行実行 |
|---------|---------|
| ソースコード変更（異なるファイル） | OK |
| ソースコード変更（同一ファイル） | 非推奨 |
| DB マイグレーション | **禁止** |
| DB マイグレーション + 通常変更 | OK（マイグレーション側を先にマージ） |

---

### ブロック時の通知義務

作業が進められない状況では、**黙って停止せず即座にユーザーに報告する。**

- 自力で解決できそう → 1回だけ試みる → 解決しなければ報告
- 他チャットへの影響・設計判断 → 即座に報告
- 判断に迷う → 報告（報告しすぎは許容、沈黙は許容しない）

```
⚠️ [ブロック / 要確認]
状況: （何が起きているか）
原因: （わかっている範囲で）
影響: （作業にどう影響するか）
選択肢: （ユーザーが選べる対応案）
```

---

## 4. Database

### DB接続先の確認ルール

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

### .env の接続先ルール

- 全環境の `.env` の `DATABASE_URL` は常に**STG DB固定**。書き換え禁止
- PRD DB への操作はコマンド単位で環境変数を渡す:
  ```bash
  DATABASE_URL="prd接続文字列" node scripts/xxx.js
  ```

### ORM_TYPE=prisma の場合

- `prisma db push` 禁止。必ず `prisma migrate dev --name <説明>` を使用
- マイグレーション名: 英語スネークケース
- 生SQL（`$queryRaw` / `$executeRaw`）は原則禁止

---

## 5. Deploy Strategy

### マイグレーションとデプロイの順序

**Expand-Contract パターン**で安全にリリースする。

| 変更の種類 | デプロイ手順 |
|-----------|------------|
| 追加系（非破壊的） | 先にマイグレーション → 後にデプロイ |
| 削除/変更系（破壊的） | 2段階リリース（Expand-Contract） |

**破壊的変更**: DROP COLUMN/TABLE、ALTER TYPE、RENAME、NOT NULL追加
**非破壊的変更**: ADD COLUMN、ADD VALUE、CREATE TABLE/INDEX

### バックフィルスクリプトのルール

- 必ず `scripts/` にコミットする（使い捨て禁止）
- `--dry-run` オプションを実装する
- 本番リリース完了後も削除しない

---

## 6. Documentation Strategy

### CLAUDE.md と MEMORY.md の使い分け

| | CLAUDE.md | MEMORY.md |
|---|---|---|
| **Git管理** | される（チーム共有） | されない（個人ローカル） |
| **スコープ** | プロジェクトのルール・規約 | Claude の学習メモ・補足 |
| **寿命** | プロジェクトと同じ | 会話をまたいで永続 |

### ADR（Architecture Decision Records）

仕様に関する判断の「なぜ」を `docs/decisions/` に記録する。

- `/record-decision` スキルで記録
- ADR は仕様書の「なぜ」を補完するもの。仕様書の代わりにはならない

### NOTION_ENABLED=true の場合

- 設計書の正（Source of Truth）は Notion とする
- 仕様変更を含む実装をした場合、該当する Notion 設計書も更新する
- 更新時は必ず「更新履歴」セクションに1行追加する

---

## 7. Naming Conventions

### LANGUAGE=typescript の場合

| 対象 | 規則 | 例 |
|------|------|-----|
| 変数・関数 | `camelCase` | `getUserName` |
| 型・インターフェース | `PascalCase` | `UserProfile` |
| コンポーネントファイル | `PascalCase.tsx` | `Button.tsx` |
| その他のファイル | `kebab-case` | `user-service.ts` |
| ディレクトリ | `kebab-case` | `user-profile/` |
| 定数 | `SCREAMING_SNAKE_CASE` | `MAX_RETRY_COUNT` |
| 未使用引数 | `_` プレフィックス | `_unused` |

### LANGUAGE=python の場合

| 対象 | 規則 | 例 |
|------|------|-----|
| 変数・関数 | `snake_case` | `get_user_name` |
| クラス | `PascalCase` | `UserProfile` |
| ファイル | `snake_case` | `user_service.py` |
| 定数 | `SCREAMING_SNAKE_CASE` | `MAX_RETRY_COUNT` |

### 共通

- 変数名・関数名は**英語（ASCII）**で書く。日本語ローマ字は使わない
- コメントは日本語OK

---

## 8. Lessons Learned

<!-- プロジェクト固有の事故事例・教訓をここに追記する -->
<!-- フォーマット: 何が起きたか → 根本原因 → 改善策 -->

---

## 9. 外部タスク管理連携（Layer 2 オプション）

> **標準構成（Layer 0）**: sidekick は MEMORY.md + GitHub Issues だけで完結する。
> Notion 等の外部DB連携は、非エンジニアとのタスク共有が必要な場合のオプション拡張。

Notion 等の外部タスク管理DBと連携してタスク状態を共有する場合のプロトコル。
`NOTION_ENABLED: false`（デフォルト）のプロジェクトではこのセクション全体をスキップしてよい。

> **設定方法**: `.claude/rules/` にプロジェクト固有の連携設定ファイルを配置する。
> テンプレート: `.claude/rules/task-db-integration.md.example` を参照し、`.claude/rules/` 配下に設定ファイルを作成する

### 作業開始時
1. タスクDBから自PJの Status=Todo|Doing タスクを取得
2. Instruction Detail があればその内容に従う
3. 着手するタスクの Status → Doing に更新
4. **Sourceタグを記録**: Active Work に取り込む際、出典を明示する
   - `[TasksDB] notion.so/xxx` — タスクDB由来
   - PJ固有DBがあれば `[ProjectDB]` 等のタグも併用

### 作業完了時
1. Status → Done
2. Completion Note に結果を記録（何をやったか・変更点・影響範囲）

### ブロック発生時
1. Blocker Type を選択（なし/情報不足/仕様判断待ち/リリース判断/技術詰まり/外部待ち/実行許可待ち）
2. Blocker Detail に具体的内容を記録
3. Status → Waiting

### セッション終了時
1. Next Action を更新（次回何から始めるかの引き継ぎメモ）
2. `/close-chat` Step 6 で タスクDB への同期を実行する
