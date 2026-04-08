---
name: news
description: "コードベースを最新化し、直近の変更内容をわかりやすくサマリ表示する。"
user-invocable: true
---

# /news — 最新の変更を取り込み・サマリ表示

## 実行方式

このスキルは **Agent ツールで隔離実行する**。
メインコンテキストを保護するため、以下の手順で実行すること:

1. Agent ツールを起動し、このスキルの全手順（Step 1〜6）を渡す
2. Agent はスキルの手順を実行し、Return Contract に従って結果を返す
3. メインコンテキストには結果サマリのみが残る

## 目的

`git pull` でコードベースを最新化し、前回からの変更内容をわかりやすくサマリ表示する。

## 手順

### Step 1: 現在のHEADを記録

```bash
# プロジェクトのメインブランチに合わせて変更（main / master / develop 等）
MAIN_BRANCH=main
OLD_HEAD=$(git rev-parse origin/$MAIN_BRANCH)
```

### Step 2: 最新コードを取り込み

```bash
git pull --ff-only origin $MAIN_BRANCH
```

### Step 3: 新しいHEADを取得

```bash
NEW_HEAD=$(git rev-parse origin/$MAIN_BRANCH)
```

### Step 4: 差分の有無を判定

- `OLD_HEAD` と `NEW_HEAD` が同一の場合 → 「新しい変更はありません。最新の状態です。」と表示して終了
- 異なる場合 → Step 5 に進む

### Step 5: 変更内容を収集

以下のコマンドで情報を収集する:

```bash
# マージされたPR一覧
git log $OLD_HEAD..$NEW_HEAD --merges --oneline

# 個別コミット一覧（マージコミット除く）
git log $OLD_HEAD..$NEW_HEAD --oneline --no-merges

# DB変更の有無（ORM使用プロジェクトの場合）
git diff $OLD_HEAD..$NEW_HEAD -- prisma/migrations/ migrations/ db/migrate/ --stat 2>/dev/null

# API変更の有無
git diff $OLD_HEAD..$NEW_HEAD -- 'app/api/' 'src/api/' 'routes/' --stat 2>/dev/null

# UI変更の有無
git diff $OLD_HEAD..$NEW_HEAD -- 'app/' 'src/' 'components/' 'pages/' --stat 2>/dev/null
```

### Step 6: サマリを生成・表示

コミットメッセージの conventional commit prefix で自動分類する:

| prefix | カテゴリ |
|--------|---------|
| `feat:` | 新機能 |
| `fix:` | バグ修正 |
| `refactor:` / `perf:` | 改善 |
| `docs:` / `chore:` / `ci:` | その他 |

## 出力フォーマット

```
=== 最新の更新 (YYYY-MM-DD) ===

前回からの変更: X件のコミット、Y件のPRマージ

[NEW] 新機能:
- （feat: コミットから抽出。1行要約）

[FIX] 修正・改善:
- （fix: / refactor: コミットから抽出）

[DB] DB変更: あり / なし
  （ありの場合: マイグレーション名を列挙）

[API] API変更: あり / なし
  （ありの場合: 追加・変更されたエンドポイントを列挙）

[UI] UI変更: あり / なし

=== マージされたPR ===
- #NNN: タイトル
- #NNN: タイトル
```

## 注意事項

- このスキルはメインブランチでの使用を前提とする
- 初回実行時（クローン直後など）は差分がないため「最新の状態です」と表示される
- 技術的な詳細（ファイルパス、変数名等）は省略し、ユーザーに見える変化を中心にサマリする
- コミットメッセージが英語の場合は、プロジェクトの言語に合わせて意訳する

---

## Return Contract

### 返すもの
- 出力フォーマットに従ったサマリ（カテゴリ別変更一覧、DB/API/UI変更有無、マージPR一覧）
- 差分がない場合は「新しい変更はありません。最新の状態です。」のみ

### 返さないもの
- git log / git diff の生出力
- 個別コミットの詳細な差分内容
- ファイルパスの羅列（stat 出力そのまま等）