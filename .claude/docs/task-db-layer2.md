# 外部タスク管理連携（Layer 2）+ 判断ログ同期 — 詳細プロトコル

> `.claude/rules/task-management.md`（Layer 0）から分離した Layer 2 の遅延ロード doc。**常駐しない**。
> `NOTION_ENABLED=true` または `NOTION_JUDGMENT_SYNC=true` の PJ でタスク連携・判断ログ同期を行うときだけ Read する。
> 既定（両フラグ false）の PJ はこの doc を無視してよい（常駐ダイエット・ADR-0023 retrieve>resident）。

---

# 外部タスク管理連携（Layer 2 オプション）

Notion 等の外部タスク管理DBと連携してタスク状態を共有する場合のプロトコル。
`NOTION_ENABLED: false`（デフォルト）のプロジェクトではこのセクション全体をスキップしてよい。

> **設定方法**: `.claude/rules/` にプロジェクト固有の連携設定ファイルを配置する。
> テンプレート: `.claude/rules/task-db-integration.md.example` を参照し、`.claude/rules/` 配下に設定ファイルを作成する

## 作業開始時
1. タスクDBから自PJの Status=Todo|Doing タスクを取得
2. Instruction Detail があればその内容に従う
3. 着手するタスクの Status → Doing に更新
4. **Sourceタグを記録**: Active Work に取り込む際、出典を明示する
   - `[TasksDB] notion.so/xxx` — タスクDB由来
   - PJ固有DBがあれば `[ProjectDB]` 等のタグも併用

## 作業完了時
1. Status → Done
2. Completion Note に結果を記録（何をやったか・変更点・影響範囲）

## ブロック発生時
1. Blocker Type を選択（なし/情報不足/仕様判断待ち/リリース判断/技術詰まり/外部待ち/実行許可待ち）
2. Blocker Detail に具体的内容を記録
3. Status → Waiting

## セッション終了時
1. Next Action を更新（次回何から始めるかの引き継ぎメモ）
2. `/close-chat` Step 6 で タスクDB への同期を実行する

---

# 判断ログ同期（Layer 2 オプション、独立フラグ）

> `NOTION_JUDGMENT_SYNC: false`（デフォルト）のプロジェクトではこのセクション全体をスキップしてよい。
> `NOTION_ENABLED` とは用途が異なる（タスクではなく判断の蓄積）ため独立フラグで制御する（ADR-0012）。

セッション中に出た**設計判断・方針判断**を Notion 判断ログDB に自動蓄積する。複数PJ横断の判断集約・外部発信（SNSネタ源等）のセカンダリ用途として位置づける。設計判断の Source of Truth は引き続き ADR（`docs/decisions/`）。

## 前提

- `NOTION_JUDGMENT_SYNC: true` かつ `NOTION_JUDGMENT_DB_URL` が設定されている
- Notion MCP 接続が有効（`NOTION_ENABLED: true` とは独立。判断ログ同期専用で MCP を使う場合もある）

## セッション終了時（`/close-chat` Step 6.5 として実行）

1. セッション中に出た判断を抽出（ADR化されなかった軽微な判断を含む）
2. Notion 判断ログDB に以下のスキーマで登録:

| プロパティ | 型 | 内容 |
|---|---|---|
| タイトル | title | 判断の短い要約 |
| カテゴリ | multi_select | 設計判断 / 方針 / 技術選定 / 表現トーン / ブランディング / プロダクト / その他 |
| コンテキスト | rich_text | セッションの話題・背景 |
| 判断 | select | OK / NG / 保留 |
| 判断理由 | rich_text | なぜその判断に至ったか |
| 学び | rich_text | この判断から得られた知見（任意） |
| 日時 | date | 判断がなされた日時 |

3. 登録結果（件数・失敗件数）をユーザーに報告

## 冪等性

- 同じ判断を複数回送信しないため、セッションごとに同期済みフラグを auto-memory に記録する
- 実装詳細は close-chat スキル内で管理

## 抽出対象の線引き

- **対象**: 設計判断・方針選択・技術選定・トレードオフ評価（複数の選択肢から1つを選んだもの）
- **対象外**: 単なる実装（「このファイルを編集した」）、調査結果、エラー解決の手順

判断か実装かの境界が曖昧な場合はユーザーに確認する。
