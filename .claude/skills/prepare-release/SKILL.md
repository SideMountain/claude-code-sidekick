---
name: prepare-release
description: "リリース準備。release/stg → main の差分集約・チェックリスト確認・リリースPR作成を対話的に実行する。マイグレーション/データパッチ/環境変数の適用漏れを防ぐ。STG_ENABLED=true の PJ 向け。"
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash
---

# リリース準備（prepare-release）

## 目的

`release/stg` → `main` のリリース PR を安全に作成する。
CLAUDE.md「Git Strategy」「Deploy Strategy（Expand-Contract）」を機械的に実行し、チェック漏れ（マイグレーション・データパッチ・環境変数の適用漏れ）を防止する。

**前提: STG_ENABLED=true（2 段階リリース）の PJ 向け。** マイグレーションのパスと本番適用コマンドは ORM_TYPE で読み替える:

| ORM_TYPE | マイグレーションのパス | 本番適用 |
|---|---|---|
| prisma | `prisma/migrations/` | `prisma migrate deploy`（H4: 自律実行禁止） |
| none（Supabase CLI） | `supabase/migrations/` | `supabase db push --db-url $PRD_DB_URL`（H20） |
| none（DB なし） | — | Step 2 は常に「なし」 |

## 前提条件

- メインワークスペース（`release/stg` ブランチ・H21）で実行すること
- メインワークスペースが最新であること（`git pull --ff-only origin release/stg`）

## 手順

以下のステップを**順番に**実行し、各ステップの結果を報告する。

### Step 0: 前提確認

```bash
git branch --show-current   # release/stg であること（H21）
git fetch origin
git pull --ff-only origin release/stg
```

- `release/stg` でない場合: 即座に停止し報告（メインWSの常駐ブランチは release/stg・H21）
- pull に失敗した場合: 報告（FF できない＝履歴乖離。原因を確認）

### Step 1: 差分集約

以下を実行し結果をまとめる。**ベースは `origin/main`、対象は `origin/release/stg`**。

```bash
git log origin/main..origin/release/stg --oneline --merges   # マージPR一覧
git log origin/main..origin/release/stg --oneline            # 全コミット一覧
git diff origin/main..origin/release/stg --stat              # ファイル変更統計
# マイグレーション差分（パスは ORM_TYPE で読み替え）
git diff origin/main..origin/release/stg -- '*migrations/*' --stat
# データパッチ/スクリプト差分
git diff origin/main..origin/release/stg -- scripts/ --stat
# 環境変数・デプロイ設定差分（ホスティング設定ファイルは PJ に合わせる）
git diff origin/main..origin/release/stg -- .env.example --stat
```

**出力フォーマット:**

```
=== リリース差分サマリ ===
含まれるPR: N本
| PR | 内容 |
|---|---|
| #XX | ... |

変更ファイル: N個
マイグレーション: あり（ファイル名 ...）/ なし
データパッチスクリプト: あり / なし
環境変数・デプロイ設定変更: あり / なし
```

### Step 2: マイグレーション確認

マイグレーションパスに差分がある場合のみ実行。

1. 追加された各マイグレーションを**実際に読み**、破壊的/非破壊的を判定する
   - 破壊的: `DROP COLUMN`, `DROP TABLE`, `ALTER ... TYPE`, `RENAME`, `NOT NULL` 制約追加
   - 非破壊的: `ADD COLUMN`, `ADD VALUE`, `CREATE TABLE`, `CREATE INDEX`, RLS/ポリシー追加
2. 破壊的変更がある場合: **Expand-Contract**（deploy-strategy.md）の 2 段階手順を提示
3. 複数マイグレーションの依存関係・適用順序を確認
4. STG への適用状況を確認（feature 開発時に適用済みのはず）。本番への適用は未実施が前提
5. 本番適用コマンドと順序を確定して報告（実行は Step 5 のリリース手順。承認はフルパッケージ = 手順・影響・ロールバック提示）
6. **書き込みを伴う列を足す Expand migration は、コードのデプロイより前に適用する**（「Expand は後方互換だから順不同」は読み取り側にしか当てはまらない。新列に書くコードが先に本番に出ると、その列が無い間そのテーブルへの書き込みが全滅する）

### Step 3: データパッチ確認

`scripts/` に差分がある場合のみ実行。

1. 各 feature PR の body（リリース手順セクション）を `gh pr view <番号>` で取得
2. データパッチの実行状況を確認（STG済み / 本番済み / 未実行）
3. 未実行のパッチがある場合: 実行手順を提示（**必ず dry-run → 本番の 2 段階**・H2）
   - 本番接続情報は**コマンド単位で**渡す（`.env` の書き換え禁止・H5）

### Step 4: 環境変数・デプロイ設定確認

`.env.example` やホスティング設定に差分がある場合のみ実行。

1. 追加・変更された環境変数を一覧化
2. **ホスティング側（Vercel 等）の本番環境変数設定が必要か**を報告（追加変数名を明示）
3. go-live 系の重要変数（外部送信のモード切替・cron スケジュール等、PJ 固有の「本番でだけ有効になるべき値」）を特に確認する

### Step 5: チェックリスト報告

全ステップの結果を集約し、以下で報告する。

```
=== リリース準備チェックリスト ===
[Step 1: 差分集約] 完了 — PR N本、変更ファイル N個
[Step 2: マイグレーション] なし / 要適用（非破壊 → 先に適用 → デプロイ）/ 要適用（破壊 → Expand-Contract）
  （対象ファイル・本番適用順序）
[Step 3: データパッチ] なし / 実行済み / 要実行（dry-run 手順）
[Step 4: 環境変数] なし / 要設定（変数名・go-live 変数の確認結果）

=== 本番リリース実行手順 ===
1. （マイグレーションがある場合）本番へ適用【手順・影響・ロールバック提示 → 明示承認】
2. （データパッチがある場合）dry-run → 本番【H2】
3. PR マージ: gh pr merge --merge   ← 通常マージのみ（squash 禁止・git-strategy.md）
4. main マージ後のデプロイ完了を確認 → 本番動作確認

総合判定: PR作成可 / ブロッカーあり
```

### Step 6: PR作成

総合判定が「PR作成可」の場合、**ユーザーに承認を求めてから**作成する（H8）。

**確認フォーマット:**
```
release/stg → main にリリースPRを作成してよいですか？
- 含まれるPR: #XX, #YY, #ZZ（計N本）
- マイグレーション: なし / あり（本番適用順序: ...）
- データパッチ: なし / 実行済み / 要実行
- 環境変数: なし / 要設定（...）
```

**PR作成（メインWSは release/stg のまま・checkout しない・H21）:**
```bash
gh pr create --base main --head release/stg --title "release: <主要変更の概要>" --body "..."
```

- 前回リリース PR がバージョン採番を使っていれば踏襲。無ければ主要変更の概要をタイトルにする
- **PR body**: 含まれる PR 一覧 / 本番リリース手順（マイグレ・データパッチ・環境変数）/ チェックリスト
- **public リポの場合は固有名詞・接続文字列・本番の識別子を body に含めない**（pii-prevention.md）

## スキルが**やらない**こと（スコープ外・ユーザーが別途実行）

- 本番マイグレーション実行（フルパッケージ承認必須）
- 本番データパッチ実行（`scripts/`）
- PR マージ（`gh pr merge`）
- main マージ後のデプロイ・本番動作確認

## 注意事項

- 全ステップを実行する（「該当なしだから省略」はしない — 「なし」と明示報告する）
- 破壊的/非破壊的の判定は **SQL/マイグレーションを実際に読んで**行う（推測しない）
- feature PR の「リリース手順」セクションを必ず確認する（PR body 記載）
- PR 作成前に必ずユーザー承認を得る（H8）
- マージは**通常マージのみ**（`--merge`）。squash 禁止（コミットハッシュが変わり 2 段階マージで衝突・git-strategy.md）

## Gotchas（見落としやすい事故パターン）

1. **dry-run 省略の提案禁止（H2）**: 「STG で確認済み」でも本番の dry-run は必須。STG と本番はデータが異なる
2. **本番マイグレーション適用は常にフルパッケージ承認**: 「手順・影響行数・ロールバック提示 → 明示承認」を毎回行う（STG 適用の承認とは別）
3. **`gh pr merge --auto` は即マージされうる**: branch protection 未設定のリポでは `--auto` が無視され即マージされる。マージ系コマンドは「確認目的」でも実行しない（H8）
4. **`release/stg` を消さない**: リポの auto-delete 設定（`delete_branch_on_merge`）が ON だとリリースマージで release/stg が消える。2 段階リリースのリポでは OFF 運用にし、リリースマージ後も release/stg を残す
5. **HARD ルールに効率最適化判断を適用しない**: 「さっき確認した」「同じWSだから」は省略理由にならない
6. **接続文字列は `.env` を書き換えず**コマンド単位で渡す（H5）。`.env` は常に STG 固定
