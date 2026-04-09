---
name: inventory
description: "タスク棚卸し + sidekickバージョンチェック。Tasks DB・GitHub Issues・Backlogを横断照合し、作業全体像を一覧表示する。"
user-invocable: true
---

# /inventory — タスク棚卸し・全体像把握

## 実行方式

このスキルは **Agent ツールで隔離実行する**。
メインコンテキストを保護するため、以下の手順で実行すること:

1. Agent ツールを起動し、このスキルの全手順（Step 1〜7）を渡す
2. Agent はスキルの手順を実行し、Return Contract に従って結果を返す
3. メインコンテキストには結果サマリのみが残る

> **例外**: Step 5 で sidekick バージョン更新の承認が必要な場合、
> Agent は「更新あり」の旨をサマリに含めて返し、メインで承認を求める。

## 目的

複数のタスクソース（Tasks DB、GitHub Issues、MEMORY.md Backlog）を横断的に取得・照合し、
現在の作業全体像を一覧表示する。加えて、sidekick テンプレートの更新有無を検知する。

セッション開始時やタスクの優先順位を見直したいときに実行する。

---

## 手順

### Step 1: Tasks DB タスク取得

> **前提条件**: CLAUDE.md の `NOTION_ENABLED` が `true`、かつタスクDB連携の設定ファイル（`.claude/rules/` 配下）が存在する場合のみ実行。
> 該当しない場合はスキップし、Step 2 へ。

Tasks DB から自PJの未完了タスクを取得する。

```
フィルタ条件:
  - Project = 自PJ名（タスクDB連携の設定ファイルに記載）
  - Status = Todo OR Doing OR Waiting
```

取得したタスクを以下の形式で一時保持:

```
[TasksDB] {タスク名} | Status: {status} | Blocker: {blocker_type or なし}
  URL: {notion_url}
  Instruction: {instruction_detail の先頭100文字}
```

### Step 2: PJ固有DB タスク取得

> **前提条件**: CLAUDE.md に PJ固有の Notion DB（Tasks DB 以外）が定義されている場合のみ実行。
> 定義がない場合はスキップし、Step 3 へ。

PJ固有DBの未完了タスクを取得し、同様の形式で一時保持する。

```
[{DB名}] {タスク名} | Status: {status}
  URL: {notion_url}
```

### Step 3: GitHub Issues 取得

リポジトリの Open Issues を取得する。

```bash
gh issue list --state open --limit 50 --json number,title,labels,assignees,createdAt
```

取得した Issues を以下の形式で一時保持:

```
[Issue] #{number} {title} | Labels: {labels} | Assigned: {assignees}
```

Issue がない場合は「GitHub Issues: 0件」と表示してスキップ。

### Step 4: MEMORY.md Backlog 読み込み

MEMORY.md の `## Backlog` セクションを読み込み、未完了項目（`- [ ]`）を一時保持する。

```
[Backlog] {内容}
```

### Step 5: sidekick バージョンチェック

> **前提条件**: MEMORY.md に `sidekick_version` コメントがある場合のみ実行。
> sidekick をテンプレートとして利用していないPJ（sidekick 自身を含む）ではスキップ。

#### 5a. バージョン比較

1. MEMORY.md から `sidekick_version` コメントを読み取る（例: `<!-- sidekick_version: 0.1.0 -->`）
2. sidekick リポジトリの最新バージョンを取得する
   - **GitHub Releases API**（推奨）: `gh api repos/{owner}/sidekick/releases/latest --jq '.tag_name'`
     （`{owner}` は sidekick の GitHub オーナー名。`git remote get-url origin` から取得可能）
   - フォールバック: `gh api repos/{owner}/sidekick/tags --jq '.[0].name'`

#### 5b. 差分表示

バージョンが異なる場合、GitHub Releases のリリースノートを表示する。

```
=== sidekick 更新あり ===
現在: v0.1.0 → 最新: v0.2.0

変更内容:
  （GitHub Releases のリリースノートを表示）

更新が必要です。メインに戻って取り込み判断を行ってください。
```

> **Note**: Agent 隔離実行時、バージョン更新の取り込み判断はメインコンテキストで行う。
> Agent は差分情報をサマリに含めて返し、承認後にメインで以下を実行する:
> 1. GitHub Releases のリリースノートに基づき、手動で差分を適用する
> 2. MEMORY.md の `sidekick_version` を更新する

### Step 6: 重複検知

Step 1-4 で取得した全タスクを横断照合し、類似タスクを検出する。

**照合ロジック:**
- タスク名のキーワード一致（部分一致）
- 同一ファイル・同一機能への言及

重複候補がある場合:
```
⚠️ 重複の可能性:
  [TasksDB] "○○機能の実装" ↔ [Issue] #3 "○○を追加"
  → 同一タスクの場合、どちらかをクローズしてください
```

重複がない場合は報告不要。

### Step 7: 統合一覧表示

全ソースのタスクを統合し、以下のフォーマットで表示する。

```
=== /inventory 結果 ===

[Tasks DB] X件（Todo: X, Doing: X, Waiting: X）
  1. {タスク名} [Status] — {instruction 要約}
  2. ...

[PJ固有DB] X件（該当する場合のみ表示）
  1. ...

[GitHub Issues] X件
  1. #{number} {title} [{labels}]
  2. ...

[Backlog] X件（未完了）
  Phase 0: X件（完了/未完了）
  Phase 1: X件
  ...

[sidekick] v{current} （最新: v{latest} — 更新あり/最新です）

[重複検知] X件の候補（ある場合のみ）

===========================
推奨アクション:
  - {最も優先度の高いタスクの提案}
  - {ブロッカーがある場合の対応提案}
```

---

## 実行タイミング

- **セッション開始時**: チャット開始時の状況把握
- **手動**: ユーザーが `/inventory` を呼び出したとき
- **cron（将来）**: 毎朝の自動実行（ADR-0003 で計画済み）

## 注意事項

- Tasks DB / PJ固有DB へのアクセスは**読み取りのみ**。書き込みは行わない
- GitHub Issues が大量にある場合は `--limit 50` で制限する
- 重複検知は目安。最終判断はユーザーに委ねる
- sidekick バージョンチェックで差分適用する場合、変更内容を確認してからコミットする

---

## Return Contract

### 返すもの
- Step 7 の統合一覧（ソース別件数 + タスク一覧）
- 重複検知結果（ある場合のみ）
- sidekick バージョン差分情報（更新がある場合のみ）
- 推奨アクション

### 返さないもの
- Notion API / GitHub API の呼び出しログ
- 照合の途中経過（マッチング判定の詳細）
- 取得した生データ（JSON レスポンス等）
