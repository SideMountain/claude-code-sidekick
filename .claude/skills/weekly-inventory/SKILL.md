---
name: weekly-inventory
description: "定期棚卸し。MEMORY.md整理、feedback圧縮、知識還流フラグ処理、ADR同期確認を実行する。"
user-invocable: true
allowed-tools: "Read Edit Write Grep Glob Bash(git *) Bash(wc *) Agent"
---

# /weekly-inventory — 定期棚卸しスキル

## 目的

蓄積された運用資産（feedback、バックログ、知識還流フラグ）を定期的に圧縮・整理する。
close-chat が「セッション単位の蓄積」なら、weekly-inventory は「蓄積の圧縮」。

**実行タイミング**: 手動（ユーザーが `/weekly-inventory` を呼び出す）。目安は週1回〜月1回。

---

## 手順

### Step 0: brain（個人 brain / PJ brain）健康度チェック

brain ファイル群とフィードバックの育ち具合を確認する。

#### 0a. feedback 昇格漏れの検出

feedback_*.md を確認し、3件以上の同趣旨フィードバックが brain（PJ brain / 個人 brain）に未昇格のまま溜まっていないかチェックする。
溜まっている場合は Step 3c（昇格候補の検出）で優先的に処理する。

#### 0b. 個人 brain / PJ brain カスタマイズ状態

`~/.claude/brain/thinking.md`（個人 brain）や `<PJ>/.claude/brain/thinking.md`（PJ brain）が空 or テンプレートのデフォルトのまま（個人 / PJ 固有の判断軸が追記されていない）場合:

```
💡 brain は判断軸を定義するファイル群です。
   個人 brain (~/.claude/brain/thinking.md): 個人の判断軸（複数 PJ 横断、利用者が育てる）
   PJ brain (<PJ>/.claude/brain/thinking.md): PJ 固有の判断軸
   §1 を自分・PJ の判断軸に追記すると Claude の提案精度が変わります。
   いくつか質問に答えるだけでカスタマイズできます。やってみますか？
```

ユーザーが希望した場合、以下の3問で最小限のカスタマイズを行う:
1. 設計で最も重視すること（シンプルさ / パフォーマンス / 拡張性 / 堅牢性）
2. 迷ったときの判断基準（ユーザー影響 / スピード / 安全性）
3. やらないと決めていること（自由記入）

回答を個人 brain（複数 PJ で適用したい場合）または PJ brain（この PJ に閉じる場合）に反映する。判定の質問: **「全 PJ で適用したい判断軸か?」** YES → 個人 brain、NO → PJ brain。

### Step 0.5: sidekick 未取込更新の棚卸し

> **前提条件**: `CLAUDE.md` に `SIDEKICK_VERSION` が設定されている下流 PJ のみ。
> sidekick 本体 / `SIDEKICK_VERSION` 空の PJ ではスキップ。

全 severity（Critical / Standard / Enhancement）を横断棚卸し。`/inventory` が Critical のみ拾うのに対し、ここが**全量レポート**の責務（ADR-0009）。

```bash
CURRENT=$(grep -E "^SIDEKICK_VERSION:" CLAUDE.md | sed -E 's/.*"([^"]+)".*/\1/')
# 最新 Release 取得
LATEST=$(gh api repos/SideMountain/claude-code-sidekick/releases/latest --jq '.tag_name')
# 過去のリリース一覧（現行と最新の間にある中間バージョンも拾う）
gh api repos/SideMountain/claude-code-sidekick/releases --jq '.[] | select(.tag_name > "v'${CURRENT}'") | "\(.tag_name) \(.name)"'
```

レポート形式（**Critical は先頭に分離表示**、経過日数を併記）:

```
=== sidekick 未取込更新 ===

⚠️  Critical リリース（即取り込み推奨）:
  v0.5.1 — 2026-04-10 (8日経過) ← ⚠️ 長期未取込。即対応推奨
    Highlights: stop hook 無限ループ修正
    変更: 2ファイル
    → /adopt-sidekick-update

Standard:
  v0.6.0 — 2026-04-18 (0日前)
    Highlights: /adopt-sidekick-update 導入 + /inventory severity 対応
    変更: 23ファイル

Enhancement（opt-in、後回し可）:
  v0.7.0 — 2026-04-25 (当日)
    Highlights: /token-audit の minor 改善
    変更: 2ファイル

永久スキップ: X件
後回し（defer_until 経過）: Y件 ← 要対応
後回し（defer_until 未到来）: Z件
```

**Critical 経過日数の警告基準**（ADR-0009 P3 検知層）:
- 0-2日: 通常表示
- 3-7日: 「取り込み遅延、検討ください」
- 8日〜: 「⚠️ 長期未取込。本番影響の可能性。即対応推奨」

経過日数は release の `published_at` と現在日時の差で計算（Linux / macOS 両対応）:
```bash
PUBLISHED=$(gh api repos/SideMountain/claude-code-sidekick/releases/tags/${TAG} --jq '.published_at')
PUB_EPOCH=$(date -d "$PUBLISHED" +%s 2>/dev/null \
  || date -jf "%Y-%m-%dT%H:%M:%SZ" "$PUBLISHED" +%s 2>/dev/null \
  || printf '0')
DAYS=$(( ($(date +%s) - PUB_EPOCH) / 86400 ))
```

**`auto-memory/project_skipped_updates.md` の棚卸し**:
- 永久スキップが PJ 性質変化で不要になった可能性のある項目（例: UI 追加後に `review-design` スキップが残っている）を報告
- 後回しで `defer_until` を過ぎているのに未対応の項目を報告

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

brain（PJ brain / 個人 brain / OSS テンプレート還流）に昇格済みの feedback を確認:
- 昇格済みと明記されているか
- feedback の内容と brain ファイルの記述に乖離がないか

#### 3b. 統合候補の検出

同趣旨のfeedbackが複数ないか確認。統合候補があれば提案:
```
=== feedback 統合候補 ===
1. feedback_A + feedback_B → 「○○」として統合
   理由: 同趣旨。Aの方が具体的なので A をベースに B の事例を追記
```

#### 3c. brain 昇格候補の検出

昇格判定基準・統合ルール・確認フォーマットは `references/feedback-compression-rules.md` を参照。3 件以上溜まった同趣旨 feedback を PJ brain / 個人 brain / OSS テンプレート還流候補のいずれかに昇格させる。

### Step 4: 知識還流フラグ処理

Backlog 内の `[OSS 還流候補]` `[個人 brain 昇格]` `[PJ 固有]` プレフィックス付き項目を一括確認。

```
=== 知識還流フラグ ===
[OSS 還流候補] (業界共通 → sidekick OSS テンプレートへ手動 PR):
1. 内容 → OSS テンプレート (sidekick `brain/thinking.md`) のどこに反映するか

[個人 brain 昇格] (複数 PJ 横断):
1. 内容 → 個人 brain (`~/.claude/brain/thinking.md`) への昇格

[PJ 固有] (PJ ドメイン依存):
1. 内容 → PJ brain (`<PJ>/.claude/brain/thinking.md`) への昇格

─────────────────
まとめて処理しますか？ 個別に判断しますか？
```

### Step 4.5: Tasks DB 棚卸し

> **前提条件**: CLAUDE.md の `NOTION_ENABLED` が `true`、かつタスクDB連携の設定ファイル（`.claude/rules/` 配下）が存在するプロジェクトのみ実行する。
> 該当しない場合はこのステップをスキップする。

- `[Tasks DB投入]` フラグ付きのMEMORY.md Backlog項目を確認
- オーナーに投入を依頼すべきか、自分でDB投入するか判断
- Tasks DBの Doing タスクで24h以上更新がないものを検出して報告

### Step 5: ADR / CHANGELOG / README 整合性確認

#### 5a. ADR 同期確認

```bash
# 直近追加された ADR
git log --all --diff-filter=A -- docs/decisions/*.md --format="%h %s" | head -10

# ステータスが「検討中」の ADR
grep -l "検討中" docs/decisions/*.md 2>/dev/null

# docs/decisions/ にあるが README.md 索引に無い ADR を検出
if [ -f docs/decisions/README.md ]; then
  for adr in docs/decisions/????-*.md; do
    name=$(basename "$adr")
    grep -q "$name" docs/decisions/README.md || echo "⚠️ 索引未反映: $name"
  done
fi
```

- 「検討中」のまま放置されている ADR を報告
- `docs/decisions/README.md` の索引に未反映の ADR を報告
- Notion 連携プロジェクトの場合、未同期の ADR を検出

#### 5a-2. CHANGELOG drift 検出

```bash
# 最新タグ以降のマージコミット
if [ -f CHANGELOG.md ]; then
  latest_tag=$(git describe --tags --abbrev=0 2>/dev/null)
  if [ -n "$latest_tag" ]; then
    merges=$(git log "${latest_tag}..HEAD" --merges --oneline 2>/dev/null | wc -l)
    unreleased_section=$(grep -c "^## \[Unreleased\]" CHANGELOG.md 2>/dev/null)
    if [ "$merges" -gt 0 ] && [ "$unreleased_section" -eq 0 ]; then
      echo "⚠️ CHANGELOG drift: 最新タグ以降に $merges 件のマージがあるが [Unreleased] セクション無し"
    fi
  fi
fi
```

- `[Unreleased]` セクションに未反映の変更があれば報告
- タグ以降の変更と CHANGELOG の内容差を可視化

#### 5a-3. README stale 検出（下流 PJ 向け）

```bash
# README.md の最終更新日
if [ -f README.md ]; then
  readme_mtime=$(git log -1 --format=%ct -- README.md 2>/dev/null)
  head_mtime=$(git log -1 --format=%ct 2>/dev/null)
  if [ -n "$readme_mtime" ] && [ -n "$head_mtime" ]; then
    diff_days=$(( (head_mtime - readme_mtime) / 86400 ))
    if [ "$diff_days" -gt 60 ]; then
      echo "⚠️ README.md が $diff_days 日更新されていません。プロジェクト状況の反映を検討してください"
    fi
  fi
fi
```

- README が 60日以上更新されていない場合、プロジェクト概要の最新化を提案
- `docs/` 配下の主要ファイルも同様に検出（拡張可）

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
  - OSS 還流候補: X件
  - 個人 brain 昇格: X件
  - PJ 固有: X件

[ADR] X件の要対応

─────────────────
上記を実行してよいですか？
```

ユーザー承認後に一括実行する。

### Step 7: 棚卸し日の記録

MEMORY.md に最終棚卸し日を記録する。

---

## Return Contract

weekly-inventory は Step 1-5 を Agent に委譲する場合がある。その際のデータ契約:

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