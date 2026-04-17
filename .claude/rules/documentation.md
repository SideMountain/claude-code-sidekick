# Documentation Strategy

## ドキュメントレイヤーの使い分け

| | CLAUDE.md | CLAUDE.local.md | auto-memory |
|---|---|---|---|
| **置き場所** | project root | project root | `~/.claude/projects/<slug>/memory/` |
| **Git管理** | される（チーム共有） | されない（個人ローカル） | されない（個人ローカル） |
| **スコープ** | プロジェクトのルール・規約・設定 | 応答設定・個人 MCP・環境メモ・sidekick_version | Active Work / Backlog / Memory Index（feedback/reference 等） |
| **更新主体** | 人 + Claude（合意の上） | 個人 | Claude（自動） |
| **寿命** | プロジェクトと同じ | プロジェクトと同じ | 会話をまたいで永続（棚卸しで整理） |

auto-memory は Claude Code 標準機能。types: `user` / `feedback` / `project` / `reference` が個別ファイルで保持され、`MEMORY.md` が索引となる（詳細は `knowledge-map.md` 参照）。

## ADR（Architecture Decision Records）

仕様に関する判断の「なぜ」を `docs/decisions/` に記録する。

- `/record-decision` スキルで記録
- ADR は仕様書の「なぜ」を補完するもの。仕様書の代わりにはならない

## NOTION_ENABLED=true の場合

- 設計書の正（Source of Truth）は Notion とする
- 仕様変更を含む実装をした場合、該当する Notion 設計書も更新する
- 更新時は必ず「更新履歴」セクションに1行追加する