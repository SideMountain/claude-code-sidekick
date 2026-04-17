# 外部タスク管理連携（Layer 2 オプション）

> **標準構成（Layer 0）**: sidekick は auto-memory + GitHub Issues だけで完結する。
> Notion 等の外部DB連携は、非エンジニアとのタスク共有が必要な場合のオプション拡張。

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
