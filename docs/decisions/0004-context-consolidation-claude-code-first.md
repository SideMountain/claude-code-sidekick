# ADR-0004: トリガーはClaude Code、DBはNotion（コンテキスト集約方針）

## ステータス

承認済み（2026-04-07）

## 背景

現在、思考・判断のコンテキストが複数の場所に分散している:
- Notion AI: 壁打ち、判断ログ、SNSネタ出し
- Claude Code: コード実装、レビュー、CLAUDE.md / MEMORY.md による学習
- ADR（docs/decisions/）: 技術判断の記録

同じ判断についてNotion AIとClaude Codeの両方に断片が存在し、「あの判断どこで話したっけ？」が起きる。また、Notion AIのセッションに閉じたコンテキストはClaude Codeから参照できない。

## 検討内容

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| 現状維持（Notion AI + Claude Code 併用） | 使い分け可能 | コンテキスト分散が続く |
| 全てNotion AIに寄せる | Notionに集約 | コード操作ができない。MCPの逆方向 |
| **全てClaude Codeに寄せる（Notion はDB）** | コンテキスト一元化。コード操作も可能 | Notion AI の壁打ち機能を捨てる |

## 決定

### 原則: 「トリガーはClaude Code、DBはNotion」

```
Claude Code（トリガー・思考の主体）:
  - 壁打ち・思考の整理 → セッション内で完結
  - 判断ログの記録 → Notion DBにMCP経由で書き込み
  - SNS記事ネタの記録 → Notion DBにMCP経由で書き込み
  - ADR記録 → docs/decisions/（Git管理。今のまま）
  - feedback記録 → feedback_*.md（今のまま）

Notion（DB・ビューア・共有レイヤー）:
  - Tasks DB: タスク状態管理（今のまま）
  - Projects DB: PJ状態管理（今のまま）
  - 判断ログDB: Claude Codeが書き込み、オーナーが閲覧
  - SNSネタDB: Claude Codeが書き込み、記事化時に参照
  - 設計書: SoTとして維持

Notion AI: 使わない
  → コンテキストの分散が消える
```

### ADR vs 判断ログの使い分け

```
ADR（docs/decisions/）:
  - 「なぜこの設計にしたか」
  - コードに紐づく技術判断
  - Git管理される
  - /record-decision スキルで記録

判断ログ（Notion DB）:
  - 「なぜこの方針にしたか」
  - 事業判断、運用判断、採用判断
  - コードに紐づかないこともある
  - SNS発信のネタになる
  - Claude Codeが /close-chat 等でMCP経由で記録
```

## 理由

- Claude CodeはMCP経由でNotionを操作できるため、「トリガーをClaude Code、DBをNotion」にすれば両方の強みを活かせる
- Notion AIを使わないことでコンテキストの分散を完全に防げる
- SNS運用の記事構成もClaude Codeに寄せれば、コードの文脈と発信の文脈が同一セッションで繋がる
- 判断ログをNotion DBに置くことで、オーナーがNotionのビューで横断的に閲覧できる

## 影響

- Notion AIの利用を段階的に停止
- /close-chat に判断ログDB書き込みステップを追加（各PJで判断ログDBが設計された後）
- SNS運用のワークフローをClaude Code起点に変更
- 各PJの .claude/rules/ にNotion DB IDの設定を追加（判断ログDB等）
- 具体的なNotion DB構成は本ADRのスコープ外。各PJで別途設計する
