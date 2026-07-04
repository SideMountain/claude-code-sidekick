# コンテキスト管理ガイドライン

Claude Code のコンテキストウィンドウは有限。長時間セッションで溢れないよう管理する。

## ルール（GUIDE グレード）

### ファイルサイズの目安

- CLAUDE.md, auto-memory MEMORY.md, rules/*.md は **各200行以内** を目標にする
- 超えそうな場合は分割（rules/ へ切り出し、auto-memory MEMORY.md は棚卸しで圧縮）
- スキル SKILL.md も200行以内。超える場合は `references/` に分離する

### セッション中のコンパクション

- `/context` でトークン使用量を随時確認できる
- **~60% 消費時点**: 先回りで手動コンパクション（`/compact`）を検討する（auto の 80% を待たない）。閾値の根拠と自律ループでの扱いは `context-economy.md` §4 を一次ソースとする（数値はここと統一）
- **70% 超過**: 新規の大きな探索タスクは避ける。残りのコンテキストで完了できる作業に集中する

### スキル記述の効率

- スキルの `description` はコンテキストに常駐する。簡潔かつ的確に書く
- スキル本文（SKILL.md の中身）は呼び出し時のみロードされるため、詳細はそちらに書く
- `references/` はスキル本文から明示的に読んだ場合のみロードされる（さらに遅延）

### 大規模PJでの注意

- 多数のスキルがある場合、`SLASH_COMMAND_TOOL_CHAR_BUDGET` の上限（15,000文字）に注意
- 不要なスキルは `user-invocable: false` にして description の常駐を避ける
### rules/skills の公式フォーマット準拠

- rules ファイルを新規作成・更新する際は、path-scoped（`paths:` frontmatter）が適用できるか検討する
- skills ファイルを新規作成・更新する際は、`allowed-tools` を frontmatter に含める
- 公式ドキュメントのサポート対象フィールドを確認してから記述する
