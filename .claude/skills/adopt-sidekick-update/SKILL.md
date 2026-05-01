---
name: adopt-sidekick-update
description: "下流PJが sidekick の新しいリリースを取り込む対話型スキル。カテゴリ一括判断を基本にしつつ、必要な部分だけファイル単位の対話も可能。スキップ記録は auto-memory に保持。"
user-invocable: true
allowed-tools: "Read Edit Write Grep Glob Bash(git *) Bash(gh *)"
---

# /adopt-sidekick-update — sidekick 更新取り込みスキル

## 目的

下流 PJ が `/inventory` または `/weekly-inventory` で検知した sidekick の新リリースを、**対話的に安全に取り込む**。

- **カテゴリ一括判断**（ADR / rules / skills / その他）を基本にし、億劫な「ファイル1件ずつ」を避ける
- 必要なカテゴリだけ**ファイル単位の深掘り**に入れる
- スキップした項目は auto-memory の `project_skipped_updates.md` に記録（詳細 → `references/skip-record-format.md`）
- Critical リリースは強調表示、スキップには reason 必須

ADR-0009 P2 の中核実装。

## 実行モード

- **default**: カテゴリ一括 UX（最速経路）
- **--all**: 全カテゴリ自動適用（確認なし。ただし Critical 時は警告）
- **--careful**: ファイル単位ループ（すべて個別判断）

---

## 前提

- 下流 PJ である（`CLAUDE.md` の `SIDEKICK_VERSION` が空でない）
- `ccs` が git remote として登録されている（`/setup` で自動設定）
- ccs remote が未設定なら Step 0 で案内して終了

---

## 手順

### Step 0: 前提確認

```bash
# ccs remote 確認
if ! git remote | grep -q "^ccs$"; then
  echo "❌ ccs remote 未設定。以下で設定:"
  echo "  git remote add ccs https://github.com/SideMountain/claude-code-sidekick.git"
  exit 1
fi

# SIDEKICK_VERSION 取得
CURRENT=$(grep -E "^SIDEKICK_VERSION:" CLAUDE.md | sed -E 's/.*"([^"]+)".*/\1/')
LATEST=$(gh api repos/SideMountain/claude-code-sidekick/releases/latest --jq '.tag_name')
```

最新と同じなら「取り込み済み」と表示して終了。

### Step 1: severity 判定

```bash
TITLE=$(gh api repos/SideMountain/claude-code-sidekick/releases/latest --jq '.name')
case "$TITLE" in
  *"[CRITICAL]"*) SEVERITY="Critical" ;;
  *"[ENHANCEMENT]"*) SEVERITY="Enhancement" ;;
  *) SEVERITY="Standard" ;;
esac
```

**Critical の場合**: ユーザーに「⚠️ Critical 検出。即取り込み推奨」と表示、スキップ選択時は reason 必須。

### Step 2: 差分抽出 + カテゴリ分類

```bash
git fetch ccs --tags
RANGE="v${CURRENT}..${LATEST}"

ADRS=$(git diff --name-only --diff-filter=AM "$RANGE" -- 'docs/decisions/*.md' | sort -u)
RULES=$(git diff --name-only --diff-filter=AM "$RANGE" -- '.claude/rules/*.md' | sort -u)
SKILLS=$(git diff --name-only --diff-filter=AM "$RANGE" -- '.claude/skills/' | grep 'SKILL.md$\|references/' | sort -u)
OTHER=$(git diff --name-only --diff-filter=AM "$RANGE" -- 'CLAUDE.md' 'README.md' 'README.ja.md' 'docs/migrations/' | sort -u)
```

### Step 3: 前回スキップ項目の再提示

`auto-memory/project_skipped_updates.md` から読み取り:

- **永久スキップ**: 表示のみ、適用対象から除外
- **後回し（`defer_until` 経過 or 新バージョン）**: 「前回スキップ」として先頭に再提示、[適用 / 永久スキップ / 後回し] 選択

後回しを処理してから Step 4 へ進む。

### Step 4: カテゴリ一括判断（**default モードの核心**）

カテゴリごとにサマリ + 一括判断プロンプト:

```
=== 変更サマリ (Severity: Standard) ===

[ADR] 3件
  - 新規: ADR-0010 リリース粒度の方針
  - 改訂: ADR-0001, ADR-0005
  → [Y]全適用 / [n]個別判断 / [s]全スキップ
  > _

[rules] 11件
  - 更新: code-quality.md, documentation.md, ... (全11件)
  → [Y]全適用 / [n]個別判断 / [s]全スキップ
  > _

[skills] 14件
  - 更新: adopt-sidekick-update, inventory, ... (全14件)
  → [Y]全適用 / [n]個別判断 / [s]全スキップ
  > _

[その他] 5件
  - CLAUDE.md, README.md, README.ja.md, CHANGELOG.md, ...
  → [Y]全適用 / [n]個別判断 / [s]全スキップ
  > _
```

**Enter 連打 = 全カテゴリ全適用**（最速経路）。
**n を選んだカテゴリのみ** Step 5（個別）に進む。

### Step 5: 個別判断（Step 4 で n を選んだカテゴリのみ）

当該カテゴリのファイルを 1 件ずつ提示:

```
[ADR 2/3] docs/decisions/0005-downstream-integration-principles.md
  [変更サマリ 2行]
  操作: a=適用 / s=永久スキップ / d=後回し / D=diff / q=カテゴリ中断
  > _
```

- **a**: `git show ccs/main:<path>` で取得 → 上書き
- **s**: reason 入力（Critical 時は必須、通常は任意） → スキップ記録
- **d**: reason 入力任意、defer_until 入力 → スキップ記録
- **D**: diff 表示後に再選択

### Step 6: 適用実行 + SIDEKICK_VERSION 更新 + Critical フラグ削除

選択が完了したら、一括適用実行:

```bash
for f in $APPLIED_FILES; do
  git show "ccs/main:$f" > "$f"
done

# SIDEKICK_VERSION を最新に
sed -i 's/^SIDEKICK_VERSION: .*/SIDEKICK_VERSION: "'"${LATEST#v}"'"/' CLAUDE.md

# Critical 未取込フラグの削除（ADR-0009 P3、検知層の解除）
if [ "$SEVERITY" = "Critical" ]; then
  FLAG="$HOME/.claude/projects/$(pwd | sed 's|/|-|g')/memory/project_critical_pending.md"
  [ -f "$FLAG" ] && rm "$FLAG" && echo "Critical フラグをクリアしました（session-start.sh の warning は停止）"
fi
```

### Step 6.5: ホーム L0 展開（ADR-0013、3 層 brain 構造）

`brain/thinking.md` が変更対象に含まれていた場合、または `~/.claude/ccs/brain/thinking.md` が未配置の場合に、ホーム L0 を最新化する。
L1（`~/.claude/brain/thinking.md`）が L0 を `@~/.claude/ccs/brain/thinking.md` で import する前提。

```bash
HOME_L0="$HOME/.claude/ccs/brain/thinking.md"
HOME_L1="$HOME/.claude/brain/thinking.md"

# L0 をホームに展開（ccs リポの最新版を反映）
if echo "$APPLIED_FILES" | grep -q '^brain/thinking\.md$' || [ ! -f "$HOME_L0" ]; then
  mkdir -p "$(dirname "$HOME_L0")"
  git show "ccs/main:brain/thinking.md" > "$HOME_L0"
  echo "L0 (base brain) をホームに展開: $HOME_L0"
fi

# L1 が未配置なら案内のみ（自動配置はしない、個人スコープなので明示的同意が必要）
if [ ! -f "$HOME_L1" ]; then
  echo ""
  echo "ℹ️  L1 (personal brain) が未配置: $HOME_L1"
  echo "   個人の判断軸を持つには以下のいずれか:"
  echo "   (i)  L0 を直接 import する薄い L1 を配置（推奨初期形）:"
  echo "        echo '@~/.claude/ccs/brain/thinking.md' > $HOME_L1"
  echo "   (ii) スキップ（L2 が直接 L0 を import するパターンに切替）"
fi
```

判断基準:
- **L0 はホーム展開を自動化してよい**: ccs 配布物（OSS）であり個人差分が乗らない。冪等な上書きで安全
- **L1 は自動配置しない**: 個人の判断軸を保持する層なので、初回展開時のみ案内し、内容は本人に委ねる

ADR-0013 の最小実装: ホーム L0 展開のみ自動化、L1 は案内のみ。

### Step 7: 取り込み結果 → commit 提案

```
=== 取り込み結果 ===
適用: X件 / 永久スキップ: Y件 / 後回し: Z件

commit メッセージ案:
  chore: sidekick vX.Y.Z 取り込み
  ...

このまま commit しますか？ [y/n/edit]
```

### Step 8: 完了サマリ + Next action

```
=== 完了 ===
vX.Y.Z-1 → vX.Y.Z
次: push & PR 作成（要承認）、/review でセルフチェック推奨
```

---

## Gotchas

- **ccs remote 必須**: Step 0 で確認、未設定なら案内して終了
- **reason 必須の条件**: Critical リリースで s/d を選んだ場合のみ（通常は任意）
- **カテゴリ一括の乱用**: Critical で Y を選ぶ前に「内容確認したか」を再確認
- **SIDEKICK_VERSION 更新漏れ**: Step 6 で必ず更新。次回 `/inventory` が同じ差分を再検知する
- **対話型なので Agent 委譲しない**: ユーザー判断が頻繁
- **永久スキップの見直し**: PJ 性質が変わったら（UI 追加等）、`/weekly-inventory` で棚卸し提案が出る
- **ホーム L0 展開のべき等性**: Step 6.5 は `brain/thinking.md` が変更されたとき、または `~/.claude/ccs/brain/thinking.md` が未配置のときのみ動く。再実行で副作用なし
- **L1 は自動配置しない**: 個人スコープのファイルを sidekick が勝手に作らない。案内のみで本人の同意を待つ

## 参考

- ADR-0009: リリース取り込み設計
- `references/skip-record-format.md`: スキップ記録フォーマット詳細
- `/inventory`: Critical 検知 + 1行サマリ（軽量）
- `/weekly-inventory`: 全 severity 含む深い棚卸し
- `/release`: リリース発信側（sidekick 保守者）
- `/setup`: ccs remote 初期設定
