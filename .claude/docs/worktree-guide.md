# Worktree 運用ガイド — 詳細手順

> `.claude/rules/git-strategy.md` から分離した Worktree 運用の遅延ロード doc。**常駐しない**。
> HARD ルール H12（新作業は Worktree）/ H13（作成→MEMORY.md 記録の順序）/ H14（マイグレ並行禁止）は CLAUDE.md（常駐）に残る。本 doc は新しい Worktree 作業に着手するとき Read する詳細手順。

---

## Worktree 運用

### 原則: 全作業 Worktree 運用

新しい作業は常に Worktree を作成。メインWSのブランチは切り替えない。

### チャット開始時の必須手順

```
ステップ1: git fetch origin && git branch --show-current
  → PROTECTED_BRANCHES のいずれかであることを確認

ステップ2: git status
  → 未コミットの変更がないか確認

ステップ3: auto-memory MEMORY.md の「Active Work」を読む
  → 他チャットの作業状況と影響範囲を把握
```

### Worktree 作成手順（確認不要）

```
ステップ1: git worktree add ../<project>-<用途> -b <branch-name> origin/<base-branch>

ステップ1.5: /add-dir ../<project>-<用途>
  → Worktree ディレクトリへの Read/Edit/Bash アクセスを許可する
  → これを省略すると、セッション中に都度ダイアログが出る
  → 夜間自動モード（--dangerouslySkipPermissions）では不要
  → /setup で settings.local.json の additionalDirectories に親ディレクトリが
    設定済みの場合、このステップは省略可（永続設定が優先される）

ステップ2: auto-memory MEMORY.md Active Work に追記
  - ブランチ名、作業内容（1行）、影響範囲、DBマイグレーション有無

ステップ3: .env をコピーし接続先を確認
  cp .env ../<project>-<用途>/.env
  grep "^DATABASE_URL" ../<project>-<用途>/.env

ステップ4: 依存インストール
  cd ../<project>-<用途> && <PACKAGE_MANAGER> install
```

**ステップ2を飛ばしてステップ3に進まない。**

### 軽量Worktreeパターン

変更対象がランタイム不要のファイルのみ（`.claude/`, `docs/`等）の場合、ステップ3-4をスキップ可。

### Worktree 最適化: シンボリックリンク（オプション）

`node_modules` 等の大容量ディレクトリをシンボリックリンクで共有すると、ディスク使用量を大幅に削減できる。
依存バージョンがブランチ間で同一の場合に有効。

```bash
# ステップ4の代替: npm install の代わりにシンボリックリンクを作成
ln -s $(realpath node_modules) ../<project>-<用途>/node_modules
```

**注意**: ブランチ間で `package.json` / `package-lock.json` が異なる場合はシンボリックリンクではなく通常の `npm install` を使うこと。

### Worktree ライフサイクル

- **原則**: ユーザーが「作業完了」と明言するまで保持。PRマージ後すぐには削除しない
- **PRマージ後**: auto-memory MEMORY.md のステータスを「STG確認待ち」に更新
- **削除**: ユーザー明言後に `git worktree remove` → ブランチ削除 → auto-memory MEMORY.md更新

### Active Work ステータス

| ステータス | 意味 |
|-----------|------|
| 作業中 | 開発・修正中 |
| STG確認待ち | PRマージ済み、動作確認待ち |
| 完了 | ユーザーが完了確認。Worktree削除実行 |

### 並行作業の制約

| 作業種別 | 並行実行 |
|---------|---------|
| ソースコード変更（異なるファイル） | OK |
| ソースコード変更（同一ファイル） | 非推奨 |
| DB マイグレーション | **禁止** |
