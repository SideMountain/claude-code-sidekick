# レビューAgent起動テンプレート

/review のオーケストレーターが各観点のAgentを起動する際のテンプレート。

## 起動テンプレート

```
このリポジトリ（{worktree_path}）で /review-{type} を実行してください。

変更ファイル: {file_list}
コミット: {commit_list}

{worktree_path}/.claude/skills/review-{type}/SKILL.md の手順に従い、
全ステップを実行して結果を出力フォーマットに従って報告してください。

PJ固有チェック: {worktree_path}/.claude/skills/review-{type}/references/ 配下に
ファイルがあれば読み込み、追加のチェック項目として実行してください。
```

## 変数

| 変数 | 取得元 |
|------|--------|
| `{worktree_path}` | 現在のワーキングディレクトリ |
| `{type}` | `code`, `test`, `ops`, `design`, `spec` のいずれか |
| `{file_list}` | `git diff $BASE_BRANCH...HEAD --name-only` の出力 |
| `{commit_list}` | `git log $BASE_BRANCH...HEAD --oneline` の出力 |

## Agent 設定

各 Agent には以下を渡す:
- 変更ファイル一覧
- コミットメッセージ
- 作業ブランチ名
- 作業ディレクトリのパス

**重要**: 各 Agent はそれぞれのスキルの SKILL.md の手順に**全て**従って実行する。省略しない。