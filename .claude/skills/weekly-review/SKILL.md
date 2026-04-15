---
name: weekly-review
description: "定期棚卸し。MEMORY.md整理、feedback圧縮、知識還流フラグ処理、ADR同期確認を実行する。"
user-invocable: true
allowed-tools: "Read Edit Write Grep Glob Bash(git *) Bash(wc *) Agent"
---

# /weekly-review — 定期棚卸しスキル

## 目的

蓄積された運用資産（feedback、バックログ、知識還流フラグ）を定期的に圧縮・整理する。
close-chat が「セッション単位の蓄積」なら、weekly-review は「蓄積の圧縮」。

**実行タイミング**: 手動（ユーザーが `/weekly-review` を呼び出す）。目安は週1回〜月1回。

---

## 手順

### Step 1: 現状スナップショット

```bash
# MEMORY.md の行数確認
wc -l <MEMORY.md のパス>

# Active Work の件数
grep -c "^\- \*\*" <MEMORY.md のパス>

# Backlog の未完了件数
grep -c "^\- \[ \]" <MEMORY.md のパス>

# feedback ファイル数
ls memory/feedback_*.md 2>/dev/null | wc -l
```

結果をユーザーに報告:
```
=== 棚卸し対象スナップショット ===
MEMORY.md: XXX行
Active Work: X件
Backlog: XX件（未完了）
feedback: XX件
前回棚卸し: YYYY-MM-DD
```

### Step 2: MEMORY.md 棚卸し

#### 2a. Active Work クリーンアップ

- 完了済みコメントが肥大化していないか確認
- 「STG確認待ち」のまま1週間以上経過しているエントリを報告
- Worktree が残っているがActive Workに記載がないもの、またはその逆を検出

```bash
git worktree list
```

#### 2b. Backlog 整理

- **完了済み項目**: `[x]` マーク付きを削除候補として提示
- **重複項目**: 同趣旨の項目が複数ないか確認
- **陳腐化項目**: 1ヶ月以上前の項目で、状況が変わっていないか確認
- **優先度の再評価**: ユーザーに「今もやりたい？」を確認

#### 2c. MEMORY.md 行数チェック

200行上限に近づいている場合:
- 完了済みコメントの圧縮
- 完了済みバックログの削除
- Critical Rules で CLAUDE.md に昇格すべきものの提案

### Step 3: feedback 圧縮

memory/feedback_*.md を全件読み込み、以下を実行する。

#### 3a. 昇格済みの整理

thinking.md §1 に昇格済みのfeedbackを確認:
- 昇格済みと明記されているか
- feedbackの内容と thinking.md の記述に乖離がないか

#### 3b. 統合候補の検出

同趣旨のfeedbackが複数ないか確認。統合候補があれば提案:
```
=== feedback 統合候補 ===
1. feedback_A + feedback_B → 「○○」として統合
   理由: 同趣旨。Aの方が具体的なので A をベースに B の事例を追記
```

#### 3c. thinking.md 昇格候補の検出

昇格判定基準・統合ルール・確認フォーマットは `references/feedback-compression-rules.md` を参照。

### Step 4: 知識還流フラグ処理

Backlog 内の `[ベース昇格]` `[思考OS還流]` プレフィックス付き項目を一括確認。

```
=== 知識還流フラグ ===
[ベース昇格]:
1. 内容 → ベーステンプレのどこに反映するか

[思考OS還流]:
1. 内容 → 思考OSのどのセクションに影響するか

─────────────────
まとめて処理しますか？ 個別に判断しますか？
```

### Step 4.5: Tasks DB 棚卸し

> **前提条件**: CLAUDE.md の `NOTION_ENABLED` が `true`、かつタスクDB連携の設定ファイル（`.claude/rules/` 配下）が存在するプロジェクトのみ実行する。
> 該当しない場合はこのステップをスキップする。

- `[Tasks DB投入]` フラグ付きのMEMORY.md Backlog項目を確認
- オーナーに投入を依頼すべきか、自分でDB投入するか判断
- Tasks DBの Doing タスクで24h以上更新がないものを検出して報告

### Step 5: ADR 同期確認 + プロセス改善

```bash
# 直近追加された ADR
git log --all --diff-filter=A -- docs/decisions/*.md --format="%h %s" | head -10

# ステータスが「検討中」の ADR
grep -l "検討中" docs/decisions/*.md 2>/dev/null
```

- 「検討中」のまま放置されている ADR を報告
- Notion 連携プロジェクトの場合、未同期の ADR を検出

#### 5b. 外部情報収集（任意）

> Web 検索が利用できない場合はスキップ。

以下のキーワードで最新の知見を収集し、適用可能なものを抽出する:
- "Claude Code" best practices / tips
- harness engineering / AI-assisted development

#### 5c. hooks ブロック実績

- 頻繁にブロックされるパターンがないか（ルールの認知不足の兆候）
- ブロックされるべきだがすり抜けているパターンがないか

### Step 6: 結果サマリ & 実行

```
=== 定期棚卸し結果 ===

[MEMORY.md] XXX行 → YYY行
  - Active Work: X件クリーンアップ
  - Backlog: X件削除、X件統合

[feedback] XX件 → YY件
  - 統合: X組
  - 昇格: X件

[知識還流] X件のフラグ
  - ベース昇格: X件
  - 思考OS還流: X件

[ADR] X件の要対応

─────────────────
上記を実行してよいですか？
```

ユーザー承認後に一括実行する。

### Step 7: 棚卸し日の記録

MEMORY.md に最終棚卸し日を記録する。

---

## Return Contract

weekly-review は Step 1-5 を Agent に委譲する場合がある。その際のデータ契約:

### 返すもの
- Step 1 のスナップショット数値（MEMORY.md行数、Active Work件数、Backlog未完了件数、feedback件数）
- Step 2 の整理候補リスト（削除・統合・陳腐化の各候補）
- Step 3 の feedback 統合候補・昇格候補
- Step 4 の知識還流フラグ一覧
- Step 5 の ADR 要対応リスト

### 返さないもの
- 実際の編集・削除操作（メインで承認後に実行）
- ユーザーへの判断依頼（メインで対話）

### 出力フォーマット
Step 6 の `=== 定期棚卸し結果 ===` テンプレートに従う。

---

## Gotchas

- **feedback ディレクトリのパス** — Agent Memory（`$HOME/.claude/projects/`）配下の `memory/feedback_*.md` を探す。プロジェクトごとにパスが異なるため、セッション開始時に確認すること
- **Backlog の完了済み項目** — `[x]` マーク付き項目を機械的に削除すると、Phase 記録としての文脈が失われる。削除前に「この完了記録は経緯として価値があるか」を判断する
- **知識還流フラグの蓄積数** — 5件以上溜まっている場合は処理を優先。放置すると MEMORY.md の行数制限に影響する
- **並行チャットの影響** — 棚卸し中に他チャットが MEMORY.md を更新する可能性がある。Step 1 のスナップショットと Step 6 の実行時で状態が変わりうる

---

## 注意事項

- **削除は提案のみ。実行はユーザー承認後**: 特にバックログの削除は判断をユーザーに委ねる
- **feedback ファイルは経緯記録として残す**: 昇格・統合しても元ファイルは削除しない
- **所要時間の目安**: 5-10分
- **圧縮しすぎない**: 重要な経緯情報を消さない