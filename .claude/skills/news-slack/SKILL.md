---
name: news-slack
description: "コードベースの直近変更を Slack Bot で投稿する。前回投稿時点（メッセージ内フィンガープリント）からの差分を生成し、指定チャンネルに通知。日次 routine 想定。"
user-invocable: true
---

# /news-slack — Slack に変更通知を投稿（Bot 経由）

非エンジニアを含む関係者に「main に何が入ったか」を日次で共有する。/news のサマリを Slack へ押し出す運用の機械化。

## 分類: タスク型（Agent 委譲）

## 実行方式

このスキルは **Agent ツールで隔離実行する**（メインコンテキスト保護）。

1. Agent ツールを起動し、このスキルの全手順を渡す
2. Agent は `scripts/run.mjs` を実行し、Return Contract に従って結果を返す
3. メインコンテキストには結果サマリのみが残る

## 引数

スキル呼び出し時の `args` 形式:

```
<channel_id> [--bootstrap] [--force] [--dry-run]
```

| 引数 | 必須 | 例 | 説明 |
|---|---|---|---|
| `channel_id` | 必須 | `C0XXXXXXXXX` | Slack channel ID（PJ の運用チャンネル。テスト用と本番用を分けるのを推奨） |
| `--bootstrap` | 任意 | flag | 強制 bootstrap（最新の fingerprint を無視して新規 seed） |
| `--force` | 任意 | flag | 差分なしでも post |
| `--dry-run` | 任意 | flag | post せずメッセージを stdout に出すだけ |

## 前提条件

- 環境変数 `SLACK_BOT_TOKEN` が設定されている（プロジェクト .env / routine の secret）
- Bot に必要な scope: `chat:write`, `channels:history`（プライベートなら `groups:history`）
- Bot が対象 channel に invite 済み
- `@slack/web-api` が install 済み（無ければ `npm i -D @slack/web-api`）
- 任意の環境変数: `NEWS_SLACK_TITLE`（通知タイトル。未設定ならリポジトリ名から生成）/ `NEWS_SLACK_API_PATH`（API 変更として数えるパス。未設定なら `src/app/api/`）

## 状態管理

最終投稿時の commit hash を Slack メッセージ末尾に **fingerprint** として埋め込む:

```
_(internal: last_commit=abc1234)_
```

次回実行時に bot 自身の最新 30 件から `last_commit=([0-9a-f]{7,40})` を抽出し、
そこから origin/main HEAD への diff を判定する。

- 利点: 外部 state 不要（git tag push なし、別 DB なし）
- 制約: bot 投稿が削除されると state ロスト → 自動 bootstrap で復旧

**bot 自身の投稿のみ参照** するため、ユーザー手動投稿の偽 fingerprint は無視される（安全）。

## 手順（Agent 実行）

### Step 1: 引数 + env 検証

- `channel_id` が `C[A-Z0-9]+` パターンに合致するか
- `SLACK_BOT_TOKEN` が設定されているか

検証 NG なら Return Contract の error を返す。

### Step 2: スクリプト実行

```bash
cd <repo_root>
node .claude/skills/news-slack/scripts/run.mjs <channel_id> [flags]
```

スクリプト内で:
1. `git fetch origin main`
2. `slack.auth.test()` で bot user_id 取得
3. `slack.conversations.history()` で channel 30 件読み、bot 自身の投稿から fingerprint 抽出
4. bootstrap / skip / post の判定
5. メッセージ生成 + post

### Step 3: 結果ハンドリング

スクリプトの最終行に JSON が出る:

```json
{"status": "posted", "channel": "...", "last_commit": "...", "commit_count": N, "pr_count": M}
{"status": "skipped", "reason": "no_diff", "last_commit": "..."}
{"status": "bootstrap", "channel": "...", "last_commit": "..."}
```

これを Return Contract のサマリとして返す。

## メッセージフォーマット

通常 post（bootstrap は見出し+説明のみ）:

```
:rocket: <タイトル>

前回からの変更: N件のコミット / M件のPRマージ

:new: 新機能:
- <feat: の subject 整形>

:wrench: 修正・改善:
- <fix: / refactor: / perf: の subject 整形>

:floppy_disk: DB変更: あり (X件のmigration)
:electric_plug: API変更: あり (Yファイル)

詳細は Claude Code で /news を実行

_(internal: last_commit=<HEAD>)_
```

省略ルール:
- feat / fix / refactor / perf 以外（chore / docs / ci / test）は表示から省く
- 1 セクションが空なら見出しごと省略
- DB / API 変更が「なし」なら行ごと省略
- commits 30 件超は「他 X 件は省略」と明示
- `release/stg` 同期 PR は merge カウントから除外

## Return Contract

### 返すもの
- スクリプトが出力した JSON 1行
- エラー時: `{"status":"error","reason":"<short>","detail":"<msg>"}`

### 返さないもの
- git fetch / git log の生出力
- Slack API のレスポンス全体
- Node の exception trace（必要部分のみ抜粋）

## 注意事項

- このスキルは `main` ブランチの origin 更新のみ観測。ローカル変更には反応しない
- 初回実行（bot からの fingerprint なし）は **過去差分を遡らず現 HEAD を seed のみ**
- bot 投稿が削除されると state ロスト → 次回自動 bootstrap で復旧
- routine から呼ぶ場合: `/schedule` で daily に `node .claude/skills/news-slack/scripts/run.mjs <channel_id>` を実行する設定を作る
