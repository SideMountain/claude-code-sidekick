---
name: setup
description: "プロジェクト初回セットアップ。ヒアリング→設定ファイル生成→MEMORY.md初期化を行う。"
user-invocable: true
---

# /setup — プロジェクト初回セットアップ

## 目的

新規プロジェクトの Claude Code 環境を対話的にセットアップする。
ヒアリングから設定ファイル生成、MEMORY.md 初期化までを一貫して行う。

## 手順

### Step 1: ヒアリング

以下の項目をユーザーに確認する。全て埋まるまで次のステップに進まない。

**必須項目:**

| 項目 | 質問 | 例 |
|---|---|---|
| プロジェクト名 | 何を作りますか？ | ECサイト、SaaS管理画面、API |
| 言語/FW | 使用する言語とフレームワークは？ | Next.js + TypeScript, Rails, Go + Echo |
| DB | DBは使いますか？ORM は？ | PostgreSQL + Prisma, MySQL + Drizzle, なし |
| ホスティング | デプロイ先は？ | Vercel, AWS, GCP, 自前サーバー |
| テスト | テストフレームワークは？ | Vitest, Jest, RSpec, go test |
| チーム規模 | 何人で開発しますか？ | 1人, 2-3人, 5人以上 |

**オプション項目:**

| 項目 | 質問 | デフォルト |
|---|---|---|
| MCP連携 | Notion, Slack, Sentry 等の MCP を使いますか？ | なし |
| ブランチ戦略 | Git-flow? GitHub-flow? | GitHub-flow（main + feature） |
| CI/CD | GitHub Actions? | なし |
| コミット規約 | Conventional Commits? | はい |

### Step 2: Project Configuration の設定

ヒアリング結果を基に以下のファイルを生成・更新する。

#### 2a. CLAUDE.md の更新

CLAUDE.md の `Project Configuration` をヒアリング結果で埋める。

- **既に CLAUDE.md が存在する場合**: 差分を提示してユーザーに確認する（上書きしない）
- **新規の場合**: テンプレートのプレースホルダーを埋める

設定項目:
- Tech Stack テーブルの更新
- ブランチ戦略の設定
- テストコマンドの設定
- 命名規則の調整
- DB/ORM 関連セクションの有効化/無効化

#### 2a-2. .gitignore の確認

既存PJに `.gitignore` がある場合、sidekick が必要とするエントリが含まれているか確認する:
- `.env`, `.env.local`
- `MEMORY.md`
- `.claude/settings.local.json`
- `.claude/rules/task-db-integration.md`（外部タスクDB連携設定）

不足があれば追記を提案する。

#### 2b. .claude/settings.local.json の生成

プロジェクトに応じた allow/deny リストを設定する:

```json
{
  "permissions": {
    "allow": ["テストコマンド", "ビルドコマンド", "リントコマンド"],
    "deny": ["本番DB操作コマンド"]
  }
}
```

#### 2c. スキル設定の調整

使わないスキルがあれば CLAUDE.md に明記する（削除はしない）。
例: DB を使わないプロジェクトでは review-code の C4 をスキップ対象とする。

### Step 3: MEMORY.md の初期化

`MEMORY.md.example` をコピーして初期化する。既に MEMORY.md が存在する場合は上書きしない。

```bash
cp MEMORY.md.example MEMORY.md
```

### Step 4: オーナー情報の記録（任意・全スキップ可）

> 「全スキップ」と言われたら即 Step 5 へ。使いながら自然に蓄積される設計なので、ここで埋まらなくても問題ない。

thinking.md §1 のカスタマイズ用。選択肢から選ぶか、自由記入か、スキップ。

| 質問 | 選択肢の例 | 記録先 |
|---|---|---|
| 設計で重視すること | シンプルさ / パフォーマンス / 拡張性 / 堅牢性 / 自由記入 | thinking.md §1 |
| 判断スピード | 70%で動く / 慎重派 / 状況による / 自由記入 | thinking.md §1 |
| 技術的負債への態度 | 返す派 / 動けば良い / 重要箇所だけ / 自由記入 | thinking.md §1 |
| テスト方針 | TDD / 後追い / 重要箇所のみ / 書かない / 自由記入 | CLAUDE.md |
| ドキュメント管理 | Notion / Google Docs / docs/ だけ / なし | CLAUDE.md §6 |

回答があれば thinking.md §1 に反映する。なければデフォルトのまま。
セッションを重ねるごとに feedback → thinking.md 昇格で自然に精緻化される。

### Step 4.5: 外部DB連携（オプション）

> **ほとんどのPJではスキップ可。** Notion等と連携したい場合のみ設定する。
> sidekick は MEMORY.md + GitHub Issues だけで全機能動作する。

連携したい場合:
1. `.claude/rules/task-db-integration.md.example` をコピーして設定を記入
2. Notion MCP が有効か確認（`claude mcp list`）
3. CLAUDE.md の `NOTION_ENABLED: true` に変更

### Step 5: 有効ルールの確認

Project Configuration に基づいて、このPJで有効になるHARDルールを一覧表示する:

```
=== 有効な HARD ルール ===
常時有効: H1, H2, H6, H7, H8, H9, H12, H13, H14, H15
ORM_TYPE=prisma: H3, H4（有効/無効）
STG_ENABLED=true: H10, H11（有効/無効）
.env保護(STG/PRD設定時): H5（有効/無効）
```

### Step 6: 確認・完了

セットアップ内容のサマリを提示し、ユーザーに確認する:

```
=== セットアップ完了 ===

プロジェクト: {name}
Tech Stack: {language} + {framework} + {db}
ブランチ戦略: {strategy}
テストコマンド: {test_command}

生成/更新したファイル:
- CLAUDE.md
- .claude/settings.local.json
- MEMORY.md

次のステップ:
1. CLAUDE.md の内容を確認し、必要に応じて調整してください
2. `git add . && git commit` でセットアップをコミットしてください
3. 開発を始めましょう
```

## 注意事項

- ヒアリングは対話的に進める。一度に全項目を聞かず、カテゴリごとに確認してもよい
- 既に CLAUDE.md が存在する場合は上書きせず、差分を提示してユーザーに確認する
- MEMORY.md が既に存在する場合は上書きしない（追記のみ）
- テンプレートの全セクションを埋める必要はない。プロジェクトに不要なセクションは「対象外」と明記する