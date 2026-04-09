---
name: setup
description: "プロジェクトセットアップ。新規PJはテンプレートから生成、既存PJは非侵襲的に追加する。"
user-invocable: true
---

# /setup — プロジェクトセットアップ

## 目的

新規または既存プロジェクトの Claude Code 環境を対話的にセットアップする。
ヒアリングから設定ファイル生成、MEMORY.md 初期化までを一貫して行う。

## 設計原則

- **何もしないがデフォルト** — 追加したいものだけ opt-in で聞く
- **既存ファイルを上書きしない** — 差分を提示してユーザーに確認する
- **背景知識不要** — 質問は「何がしたいか」で聞く（sidekick の内部構造を前提にしない）
- **.gitignore は配置と連動** — 配置しなかったファイルの gitignore パターンは追記しない

---

## 手順

### Step 0: モード判定

```
CLAUDE.md が既に存在するか？
  ├── No → 新規PJモード（Step 1 へ）
  └── Yes → 既存PJモード（Step 1E へ）
```

---

## 新規PJモード

### Step 0.5: テンプレートクリーンアップ

GitHub Template から fork した場合、sidekick 自身のファイルがルートに残っている。
以下のファイルの扱いをユーザーに確認する:

| ファイル | デフォルト案内 |
|---------|-------------|
| `CHANGELOG.md` | 「これは sidekick のリリース履歴です。削除して、プロジェクト固有の CHANGELOG を必要に応じて作成してください」 |
| `README.md` / `README.ja.md` | 「プロジェクト固有の README に差し替えてください」 |
| `.github/` | 「Issue テンプレートをそのまま使いますか？カスタマイズしますか？不要なら削除できます」 |
| `LICENSE` | 「プロジェクトのライセンスに差し替えてください」 |
| `docs/decisions/` | 「sidekick の設計判断記録です。プロジェクト固有の ADR を書く場所として残すことを推奨します（既存の ADR は削除してOK）」 |

> **判定方法**: `CHANGELOG.md` の冒頭が `# Changelog` かつ `sidekick` を含む場合、テンプレートから fork と判定する。
> 該当しない場合（既存PJモードでもない）はスキップ。

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

MCP を使う場合、`.claude/skills/setup/references/mcp-recommendations.md` を読み、
Tier に応じたインストールコマンドを案内する。

### Step 2: Project Configuration の設定

ヒアリング結果を基に以下のファイルを生成・更新する。

#### 2a. CLAUDE.md の生成

CLAUDE.md の `Project Configuration` をヒアリング結果で埋める。

設定項目:
- Tech Stack テーブルの更新
- ブランチ戦略の設定
- テストコマンドの設定
- 命名規則の調整
- DB/ORM 関連セクションの有効化/無効化

#### 2b. .claude/settings.local.json の生成

プロジェクトに応じた allow/deny リストを設定する。
また、**Worktree のディレクトリアクセス許可**のため、プロジェクトの親ディレクトリを `additionalDirectories` に自動設定する。

```bash
# 親ディレクトリの絶対パスを取得
PARENT_DIR=$(cd .. && pwd)
```

```json
{
  "permissions": {
    "allow": ["テストコマンド", "ビルドコマンド", "リントコマンド"],
    "deny": ["本番DB操作コマンド"],
    "additionalDirectories": [
      "<PARENT_DIR の値>"
    ]
  }
}
```

> **なぜ**: Worktree は `../<project>-<用途>` に作成される。親ディレクトリを信頼対象にしないと、
> WT内のファイル操作時にツール許可（Allow）とは別軸のディレクトリアクセス確認ダイアログが毎回表示される。
> `settings.local.json` は git 非追跡なので、マシン固有のパスが入っても問題ない。
>
> **`/add-dir` との関係**: `/add-dir` はセッション単位の一時的な許可。`additionalDirectories` は永続設定。
> `/setup` で後者を設定済みなら、CLAUDE.md Worktree 手順のステップ1.5（`/add-dir`）は省略できる。
>
> **注意**: 親ディレクトリ配下の他プロジェクトもアクセス対象になる。
> 秘匿情報を含むプロジェクトが同階層にある場合は、WT専用の親ディレクトリで運用することを推奨。

#### 2c. スキル設定の調整

PJの特性に応じてスキルの活用方針を案内する:
- DB を使わないPJでは review-code の DB 観点をスキップ対象とする
- auto-implement の適用範囲を案内する（「推奨ユースケース」セクション参照）

### Step 3: テンプレート配置

`.claude/templates/` から必要なファイルをルートにコピーする。

#### 3a. MEMORY.md

```bash
cp .claude/templates/MEMORY.md MEMORY.md
```

#### 3b. CLAUDE.local.md（opt-in）

「個人設定ファイル（応答言語・ローカル環境メモ）を使いますか？」と確認。
Yes の場合:
```bash
cp .claude/templates/CLAUDE.local.md CLAUDE.local.md
```

#### 3c. GitHub テンプレート（opt-in）

「GitHub Issue テンプレート（バグ報告・機能要求）とラベル定義を追加しますか？」と確認。
Yes の場合:
```bash
cp -r .claude/templates/github/.  .github/
```

### Step 4: .gitignore 連動

**Step 3 で配置したファイルに対応するパターンのみ追記する。**

必ず追記するもの（sidekick コアが必要とする）:
- `.env`, `.env.local`
- `.claude/settings.local.json`
- `.claude/agent-memory-local/`
- `.claude/skills/*/.data/`

Step 3 で配置した場合のみ追記:
- MEMORY.md を配置した → `/MEMORY.md`
- CLAUDE.local.md を配置した → `CLAUDE.local.md`

外部DB連携を設定した場合のみ追記:
- `.claude/rules/task-db-integration.md`

### Step 5: オーナー情報の記録（任意・全スキップ可）

> 「全スキップ」と言われたら即 Step 6 へ。使いながら自然に蓄積される設計なので、ここで埋まらなくても問題ない。

thinking.md §1 のカスタマイズ用。選択肢から選ぶか、自由記入か、スキップ。

| 質問 | 選択肢の例 | 記録先 |
|---|---|---|
| 設計で重視すること | シンプルさ / パフォーマンス / 拡張性 / 堅牢性 / 自由記入 | thinking.md §1 |
| 判断スピード | 70%で動く / 慎重派 / 状況による / 自由記入 | thinking.md §1 |
| 技術的負債への態度 | 返す派 / 動けば良い / 重要箇所だけ / 自由記入 | thinking.md §1 |
| テスト方針 | TDD / 後追い / 重要箇所のみ / 書かない / 自由記入 | CLAUDE.md |
| ドキュメント管理 | Notion / Google Docs / docs/ だけ / なし | CLAUDE.md §6 |

回答があれば thinking.md §1 に反映する。なければデフォルトのまま。

### Step 5.5: 外部DB連携（オプション）

> **ほとんどのPJではスキップ可。** Notion等と連携したい場合のみ設定する。
> sidekick は MEMORY.md + GitHub Issues だけで全機能動作する。

連携したい場合:
1. `.claude/rules/task-db-integration.md.example` をコピーして設定を記入
2. Notion MCP が有効か確認（`claude mcp list`）
3. CLAUDE.md の `NOTION_ENABLED: true` に変更

### Step 6: 有効ルール確認 + 完了

Project Configuration に基づいて有効な HARD ルールを一覧表示する:

```
=== 有効な HARD ルール ===
常時有効: H1, H2, H6, H7, H8, H9, H12, H13, H14, H15
ORM_TYPE=prisma: H3, H4（有効/無効）
STG_ENABLED=true: H10, H11（有効/無効）
.env保護(STG/PRD設定時): H5（有効/無効）
```

セットアップ完了サマリを提示:

```
=== セットアップ完了 ===

プロジェクト: {name}
Tech Stack: {language} + {framework} + {db}
ブランチ戦略: {strategy}
テストコマンド: {test_command}

生成/更新したファイル:
- {配置したファイル一覧}

使えるスキル:
  日常:    /review（コード・テスト・運用レビュー）
           /close-chat（セッション終了時の引き継ぎ）
           /news（最新変更のサマリ）
  自動化:  /auto-implement（設計確定済みの作業を全自動実行）
  管理:    /inventory（タスク棚卸し）
           /weekly-review（定期メンテナンス）
           /record-decision（設計判断の ADR 記録）

次のステップ:
1. CLAUDE.md の内容を確認し、必要に応じて調整してください
2. `git add . && git commit` でセットアップをコミットしてください
3. 開発を始めましょう
```

---

## 既存PJモード

CLAUDE.md が既に存在する場合。既存のファイルを尊重し、opt-in で追加のみ行う。

### Step 1E: 現状確認

既存PJの状態を調査する:

```
確認項目:
- CLAUDE.md の Project Configuration 内容
- .gitignore の sidekick 関連パターンの有無
- MEMORY.md の有無
- CLAUDE.local.md の有無
- .github/ の有無
- .claude/settings.local.json の有無
- settings.local.json に additionalDirectories（WT用）が設定されているか
```

### Step 2E: 差分案内

不足しているファイル・設定を一覧表示し、各項目を opt-in で確認する。

```
=== sidekick セットアップ（既存PJモード） ===

✅ 既に存在: CLAUDE.md, .claude/settings.json
❌ 不足: MEMORY.md, .gitignore パターン

以下を追加しますか？（個別に確認します）
```

#### 確認項目:

| 不足 | 質問（背景知識不要な聞き方） | Yes の場合 |
|------|---------------------------|-----------|
| MEMORY.md | 「セッション間で作業状態を引き継ぎたいですか？」 | `.claude/templates/MEMORY.md` → `MEMORY.md` にコピー |
| CLAUDE.local.md | 「個人の応答設定（言語等）をカスタマイズしたいですか？」 | `.claude/templates/CLAUDE.local.md` → `CLAUDE.local.md` にコピー |
| .github/ テンプレート | 「GitHub Issue テンプレートを追加しますか？」 | `.claude/templates/github/` → `.github/` にコピー（既存 .github/ がある場合はマージ方法を確認） |
| .gitignore パターン | 上記で配置したファイルに応じて自動追記 | 新規PJモードの Step 4 と同じロジック |
| settings.local.json | 「テスト・ビルドコマンドの自動許可設定を追加しますか？」 | 新規PJモードの Step 2b と同じ |
| additionalDirectories | （確認不要・自動設定） | settings.local.json に親ディレクトリを追加（Step 2b 参照） |

### Step 3E: オーナー情報（任意）

新規PJモードの Step 5 と同じ。全スキップ可。

### Step 4E: 完了サマリ

```
=== セットアップ完了（既存PJモード） ===

追加したファイル:
- {配置したファイル一覧}

追加した .gitignore パターン:
- {追記したパターン一覧}

既存ファイル（変更なし）:
- CLAUDE.md
- {その他既存ファイル}
```

---

## 注意事項

- ヒアリングは対話的に進める。一度に全項目を聞かず、カテゴリごとに確認してもよい
- 既に CLAUDE.md が存在する場合は上書きせず、差分を提示してユーザーに確認する
- MEMORY.md が既に存在する場合は上書きしない
- .github/ が既に存在する場合は、上書きせずマージ方法（追加のみ/個別選択）を確認する
- テンプレートの全セクションを埋める必要はない。プロジェクトに不要なセクションは「対象外」と明記する