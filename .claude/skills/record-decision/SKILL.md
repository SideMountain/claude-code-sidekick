---
name: record-decision
description: "仕様に関する判断を ADR（Architecture Decision Record）として docs/decisions/ に記録する。"
user-invocable: true
allowed-tools: "Read Write Bash(ls *) Bash(git *) Glob"
---

# 仕様判断の記録（/record-decision）

## 目的

会話の中で行われた仕様判断を `docs/decisions/` に ADR として記録する。
仕様の「なぜ」を後から参照可能にする。

## 手順

### Step 1: 既存ADRの確認

```bash
ls docs/decisions/
```

次の番号を決定する（4桁ゼロ埋め連番）。

### Step 2: 判断内容の整理

ユーザーに以下を確認する:
- 何について判断したか（背景）
- どんな選択肢があったか
- 何に決めたか
- なぜそう決めたか

### Step 3: ADRファイルの作成

`docs/decisions/NNNN-タイトル.md` を作成する。テンプレート:

```markdown
# ADR-NNNN: タイトル

## ステータス

承認済み（YYYY-MM-DD）

## 背景

なぜこの判断が必要になったか。問題や要件の説明。

## 検討内容

| 選択肢 | メリット | デメリット |
| ------ | -------- | ---------- |
| A案    |          |            |
| B案    |          |            |

## 決定

何をどうすることにしたか。

## 理由

なぜその選択肢を選んだか。

## 影響

- 影響するファイル・機能
- 今後注意すべき点
```

### Step 4: README.md の更新

`docs/decisions/README.md` の一覧にリンクを追記する。

```markdown
| NNNN | タイトル | 承認済み |
```

README.md が存在しない場合は作成する:

```markdown
# Architecture Decision Records

| ADR | タイトル | ステータス |
|-----|---------|-----------|
| NNNN | [タイトル](NNNN-タイトル.md) | 承認済み |
```

### Step 5: PII セルフレビュー（commit 前必須）

ADR ドラフトに個人情報・固有名詞が混入していないか、`pii-prevention.md` の `scan_pii` で検査する。

```bash
# 直近作成した ADR と README.md を対象
ADR_FILE="docs/decisions/NNNN-タイトル.md"
source <(awk '/^```bash$/{flag=1; next} /^```$/{flag=0} flag' .claude/rules/pii-prevention.md)
scan_pii "$ADR_FILE" "docs/decisions/README.md"
```

**検出ゼロが通過条件**。検出された場合:
1. 該当行を汎用表現に置換（`pii-prevention.md` の代替表現テーブル参照）
2. 判断に迷う固有名詞はユーザーに確認
3. 再スキャンしてゼロを確認してから次へ

OSS ドキュメントの作法（`oss-doc-authoring.md` SOFT）も併せて確認する。

## ファイル命名規則

```
docs/decisions/NNNN-タイトル.md
```

- NNNN: 0001 から連番（4桁ゼロ埋め）
- タイトル: kebab-case の英語（内容はプロジェクトの言語で記載）

## 注意事項

- コード実装の詳細（変数名、アルゴリズム選択等）は ADR にしない
- 仕様レベルの判断のみを記録する（「この機能はAではなくBにする」「現行仕様を維持する」等）
- ステータスは「承認済み」「検討中」「却下」「廃止」のいずれか
- 日付は必ず記載する
- 廃止する場合は元ADRのステータスを「廃止（Superseded by ADR-XXXX）」に変更する
