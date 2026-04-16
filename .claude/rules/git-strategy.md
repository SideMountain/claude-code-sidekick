# Git Strategy

## Branch Strategy

**STG_ENABLED=false の場合:**

| Branch | 用途 | 直接push |
|--------|------|----------|
| `main` | 本番 | **禁止** |
| `feature/xxx` | 機能開発。`main` から切る | OK |
| `hotfix/xxx` | 緊急修正。`main` から切る | OK |

**STG_ENABLED=true の場合:**

| Branch | 環境 | 用途 | 直接push |
|--------|------|------|----------|
| `main` | PRD | 本番 | **禁止** |
| `release/stg` | STG | 検証 | **禁止** |
| `feature/xxx` | — | 機能開発。`release/stg` から切る | OK |
| `hotfix/xxx` | — | 緊急修正。`main` から切る | OK |

## PR作成前の必須チェック（ゲート）

**1つでも NG なら PR を作成しない。**

### 0. 最新化チェック

- `git fetch origin`
- `git log <branch>..origin/<base-branch> --oneline` で未取り込みを確認
- 未取り込みがあれば `git pull --rebase origin/<base-branch>`
- **「コンフリクトがなさそうだから」でスキップしない**

### 1. 経路チェック（STG_ENABLED=true の場合）

| ターゲット | 許可されるソース |
|-----------|----------------|
| `release/stg` | `feature/*`, `hotfix/*` |
| `main` | `release/stg`, `hotfix/*` |

- **feature/* → main は禁止。例外なし。**

### 2. 差分チェック

- `git diff <target>...<source>` で意図しない変更がないか確認

### 3. ユーザー確認

- ソース→ターゲットと差分サマリを明示して承認を得る
- 「PRを作成します」ではなく「`feature/xxx` → `main` にPR作成してよいですか？（変更: ○○）」

## Merge Strategy

- **通常マージのみ**（`--merge`）。squash マージ禁止
- 理由: squash するとコミットハッシュが変わり、2段階マージでコンフリクト

## Commit Rules

- conventional commits 形式（`feat:`, `fix:`, `refactor:` 等）
- 日本語コミットメッセージ可
- 本文に「背景」「対応」「影響」を**必ず**記載
- **public リポジトリではコミットメッセージ・PR本文に固有名詞（プロダクト名・企業名・個人名・接続先情報等）を含めない**。運用プロジェクトからのバックポート時は特に注意
- **同期元リポジトリの参照を含めない**（「Synced from:」「〜から同期」等）。同期先は独立したリポとして振る舞う

```
feat: ○○機能を追加

背景: △△の問題があり、□□が必要だった
対応: ××のアプローチで実装
影響: path/to/changed/files
```

## Worktree 運用

### 原則: 全作業 Worktree 運用

新しい作業は常に Worktree を作成。メインWSのブランチは切り替えない。

### チャット開始時の必須手順

```
ステップ1: git fetch origin && git branch --show-current
  → PROTECTED_BRANCHES のいずれかであることを確認

ステップ2: git status
  → 未コミットの変更がないか確認

ステップ3: MEMORY.md の「Active Work」を読む
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

ステップ2: MEMORY.md Active Work に追記
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
- **PRマージ後**: MEMORY.md のステータスを「STG確認待ち」に更新
- **削除**: ユーザー明言後に `git worktree remove` → ブランチ削除 → MEMORY.md更新

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
| DB マイグレーション + 通常変更 | OK（マイグレーション側を先にマージ） |