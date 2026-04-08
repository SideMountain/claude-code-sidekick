# ADR-0004: Git を Source of Truth、外部 DB はオプション

## ステータス

承認済み（2026-04-07）

## 背景

AI コーディングツールを使う際、知識・判断のコンテキストが複数の場所に分散しがちである:

- Claude Code: コード実装、レビュー、CLAUDE.md / MEMORY.md による学習
- ADR（docs/decisions/）: 技術判断の記録
- 外部ツール（Notion, Linear 等）: タスク管理、設計書、判断ログ

「あの判断どこで話したっけ？」が起きる。外部ツールのセッションに閉じたコンテキストは Claude Code から参照できない。

## 検討内容

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| 外部ツールと Claude Code を併用（現状） | 使い分け可能 | コンテキスト分散が続く |
| 全て外部ツールに寄せる | 外部ツールに集約 | コード操作ができない |
| **Claude Code を主体、外部 DB はオプション** | コンテキスト一元化 | 外部ツールの壁打ち機能を捨てる |

## 決定

### 原則: 「Git が Source of Truth、外部 DB はオプションの共有レイヤー」

```
Git 管理（Source of Truth）:
  - CLAUDE.md: プロジェクトルール
  - ADR (docs/decisions/): 技術判断の記録
  - MEMORY.md: Claude のローカル作業メモ
  - feedback_*.md: 行動修正の経緯記録
  - skills/: 再利用可能なワークフロー

外部 DB（オプション。Layer 2）:
  - タスク管理（Notion, Linear 等）: 非エンジニアとの共有用
  - 設計書: Source of Truth として外部に置く場合
  - NOTION_ENABLED=true で有効化
```

### ADR vs 外部判断ログの使い分け

```
ADR（docs/decisions/）:
  - 「なぜこの設計にしたか」
  - コードに紐づく技術判断
  - Git 管理される
  - /record-decision スキルで記録

外部 DB の判断ログ（オプション）:
  - 事業判断、運用判断など
  - コードに紐づかないこともある
  - Claude Code が MCP 経由で記録
```

## 理由

- Claude Code は MCP 経由で外部 DB を操作できるため、「トリガーは Claude Code、DB は外部」にすれば両方の強みを活かせる
- Git 管理されたファイル群（CLAUDE.md, ADR, MEMORY.md）だけで基本機能が完結するため、外部 DB なしでも使える
- 外部 DB 連携をオプション（Layer 2）にすることで、テンプレートの導入ハードルを下げる

## 影響

- sidekick は外部 DB なしで完結する構成がデフォルト
- 外部 DB 連携は CLAUDE.md §9 + `.claude/rules/task-db-integration.md` で個別設定
- `/close-chat`, `/inventory`, `/weekly-review` は外部 DB 設定がある場合のみ同期ステップを実行
