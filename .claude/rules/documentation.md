# Documentation Strategy

## CLAUDE.md と MEMORY.md の使い分け

| | CLAUDE.md | MEMORY.md |
|---|---|---|
| **Git管理** | される（チーム共有） | されない（個人ローカル） |
| **スコープ** | プロジェクトのルール・規約 | Claude の学習メモ・補足 |
| **寿命** | プロジェクトと同じ | 会話をまたいで永続 |

## ADR（Architecture Decision Records）

仕様に関する判断の「なぜ」を `docs/decisions/` に記録する。

- `/record-decision` スキルで記録
- ADR は仕様書の「なぜ」を補完するもの。仕様書の代わりにはならない

## NOTION_ENABLED=true の場合

- 設計書の正（Source of Truth）は Notion とする
- 仕様変更を含む実装をした場合、該当する Notion 設計書も更新する
- 更新時は必ず「更新履歴」セクションに1行追加する