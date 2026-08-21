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

**⚠ Windows ではこの最適化は効かない**: Git Bash（MSYS）の `ln -s` は既定で symlink に
ならず**実体コピー**を作る（`fsutil reparsepoint query` が reparse point でないと応答する）。
ディスクは共有されず worktree ごとのフルコピーになるだけでなく、「リンクのつもりの実体」と
「実体のつもりのリンク」が混在して削除事故の温床になる。Windows では:

- 短命な worktree（doc / `.claude/` のみ変更）→ そもそも依存を入れない（軽量Worktreeパターン）
- ランタイムが要る worktree → 素直に `<PACKAGE_MANAGER> install` する
  （リンク由来の teardown 事故が構造的に起きない）

**⚠ 削除時の危険（Windows junction / symlink 共有時）**: リンク共有した Worktree を
リンク解除より先に `git worktree remove`（特に `--force`）すると、junction を辿って
**メインWS の実体 node_modules が削除される**（Windows 環境での実インシデント・2026-07-23）。
安全な削除順序は下記ライフサイクル節を参照。guard-bash.sh Guard 5.5 がこの順序を強制する
（`node_modules` が残っている Worktree の remove は deny される）。

### Worktree ライフサイクル

- **原則**: ユーザーが「作業完了」と明言するまで保持。PRマージ後すぐには削除しない
- **PRマージ後**: auto-memory MEMORY.md のステータスを「STG確認待ち」に更新
- **削除**: ユーザー明言後に `git worktree remove` → ブランチ削除 → auto-memory MEMORY.md更新
- **削除の安全順序（node_modules がある Worktree）**: ① node_modules のリンク・実体を先に
  明示的に除去する（junction は `cmd /c rmdir <wt>\node_modules` — リンクのみ消え実体は消えない /
  symlink は `rm <wt>/node_modules` / 実体ディレクトリは中身ごと削除） → ② 消えたことを確認 →
  ③ `git worktree remove`。junction / symlink を残したまま remove すると、リンクを辿って
  メインWS の実体が削除されうる（Guard 5.5 が deny で強制）
- **リンクか実体かの判定は機械で行う**: Windows では `fsutil reparsepoint query <path>` が
  決定的（reparse point なら成功する）。PowerShell の `(Get-Item).LinkType` は空文字を返す
  環境があり判定に使えない。判定を飛ばして再帰削除しない
- **掃除の機械化**: `.claude/scripts/cleanup-worktrees.sh`（既定 dry-run・`--apply` で実行）が
  上記の判定と安全順序、未push/未コミット/未マージ/ローカル設定（`.env.*`）の自動除外、
  共有 store の前後内容検査までを一括で行う。複数 worktree の定期掃除はこれを使う

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
