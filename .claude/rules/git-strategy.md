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

新作業は常に Worktree を作成し（**H12**・メインWSでブランチ切り替え禁止）、作成直後に auto-memory MEMORY.md の Active Work に記録する（**H13**・この順序を飛ばさない）。DB マイグレーション作業は並行禁止（**H14**）。

作成手順・軽量Worktreeパターン・シンボリックリンク最適化・ライフサイクル・ステータス・並行作業の制約の**詳細手順は `.claude/docs/worktree-guide.md`（遅延ロード・常駐しない）を参照**する（新しい Worktree 作業に着手するとき Read する）。
