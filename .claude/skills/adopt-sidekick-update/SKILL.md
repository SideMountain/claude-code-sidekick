---
name: adopt-sidekick-update
description: "下流PJが sidekick の新しいリリースを取り込む対話型スキル。カテゴリ一括判断を基本にしつつ、必要な部分だけファイル単位の対話も可能。スキップ記録は auto-memory に保持。"
user-invocable: true
allowed-tools: "Read Edit Write Grep Glob Bash(git *) Bash(gh *)"
---

# /adopt-sidekick-update — sidekick 更新取り込みスキル

## 目的

下流 PJ が `/inventory` または `/weekly-inventory` で検知した sidekick の新リリースを、**対話的に安全に取り込む**。

- **カテゴリ一括判断**（rules / skills / brain / その他）を基本にし、億劫な「ファイル1件ずつ」を避ける
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

# SIDEKICK_VERSION 取得（シングル/ダブルクォート両対応）
CURRENT=$(grep -E "^SIDEKICK_VERSION:" CLAUDE.md | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/")
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

RULES=$(git diff --name-only --diff-filter=AM "$RANGE" -- '.claude/rules/*.md' | sort -u)
SKILLS=$(git diff --name-only --diff-filter=AM "$RANGE" -- '.claude/skills/' | grep 'SKILL.md$\|references/' | sort -u)
BRAIN=$(git diff --name-only --diff-filter=AM "$RANGE" -- 'brain/' | sort -u)
PJ_MIG=$(git diff --name-only --diff-filter=AM "$RANGE" -- 'CLAUDE.md' 'README.md' 'README.ja.md' '.gitignore' 'docs/migrations/' | sort -u)

# ADR (docs/decisions/) は下流 PJ への配布対象外（ADR-0014）。
# sidekick 側 ADR の更新有無は参考表示のみ。
ADR_NOTICE=$(git diff --name-only --diff-filter=AM "$RANGE" -- 'docs/decisions/*.md' | sort -u)
```

#### PJ-protected files（盲目的上書き禁止）

下流 PJ ごとに固有値を持つファイルは **Step 6 の blind overwrite 対象外**。代わりに Step 6.4（CLAUDE.md migration）または個別案内で扱う。

| ファイル | 理由 | Step |
|---|---|---|
| `CLAUDE.md` | Project Configuration 値・PJ §1 等が PJ 固有 | 6.4 で partial merge |
| `README.md` / `README.ja.md` | PJ ごとに完全独自 | 6.4 で「上書きしない」案内のみ |
| `.gitignore` | PJ ごとにパターンが異なる | 同上 |
| `docs/decisions/` 全体 | sidekick の ADR は sidekick 自身の判断記録。下流 PJ の判断空間とは独立（ADR-0014） | 取り込み対象外。Step 6.4d で更新有無を参考表示 |
| `docs/migrations/` | sidekick が用意する移行ガイドは下流に flat に置く | sidekick → 下流の transient docs。`a` 適用 OK |

### Step 3: 前回スキップ項目の再提示

`auto-memory/project_skipped_updates.md` から読み取り:

- **永久スキップ**: 表示のみ、適用対象から除外
- **後回し（`defer_until` 経過 or 新バージョン）**: 「前回スキップ」として先頭に再提示、[適用 / 永久スキップ / 後回し] 選択

後回しを処理してから Step 4 へ進む。

### Step 4: カテゴリ一括判断（**default モードの核心**）

カテゴリごとにサマリ + 一括判断プロンプト。`[rules]` `[skills]` `[brain]` はデフォルト `[Y]全適用`、**`[PJ migration]` のみデフォルト `[n]個別判断`**（PJ 固有の上書き事故を防ぐ）。

```
=== 変更サマリ (Severity: Standard) ===

[rules] 4件
  - 新規: pii-prevention.md (HARD)
  - 更新: code-quality, knowledge-map, task-management
  → [Y]全適用 / [n]個別判断 / [s]全スキップ
  > _

[skills] 7件
  - 更新: adopt-sidekick-update, close-chat, record-decision, setup, weekly-inventory + 2 references
  → [Y]全適用 / [n]個別判断 / [s]全スキップ
  > _

[brain] 1件
  - 更新: brain/thinking.md (OSS テンプレート、Step 6.5 で個人 brain への取り込みを案内)
  → [Y]全適用 / [n]個別判断 / [s]全スキップ
  ※ PJ ローカルの brain/thinking.md はロード対象外。個人 brain (~/.claude/brain/thinking.md) は Step 6.5 で別扱い（自動上書きしない）
  ※ Step 6.4 で CLAUDE.md への @import 案内も実施
  > _

[PJ migration] 3件 ⚠️ PJ 固有内容を含むため**デフォルト個別判断**
  - CLAUDE.md (Project Configuration 値が PJ 固有 → 6.4 で partial merge)
  - README.md / README.ja.md (PJ 独自 → 通常スキップ)
  → [n]個別判断（推奨） / [Y]全適用（注意） / [s]全スキップ
  > _

[ADR] 参考: 3件更新あり（取り込み対象外、ADR-0014）
  - 新規: ADR-0010, ADR-0012, ADR-0013
  → 詳細はリリースノート / sidekick リポを参照
```

**Enter 連打 = 上 3 カテゴリ全適用 + PJ migration は個別判断**（安全な最速経路）。
**n を選んだカテゴリのみ** Step 5（個別）に進む。

### Step 5: 個別判断（Step 4 で n を選んだカテゴリのみ）

当該カテゴリのファイルを 1 件ずつ提示:

```
[rules 2/4] .claude/rules/code-quality.md
  [変更サマリ 2行]
  操作: a=適用 / s=永久スキップ / d=後回し / D=diff / q=カテゴリ中断
  > _
```

- **a**: `git show ${LATEST}:<path>` で取得 → 上書き（タグ参照でドリフト回避）
- **s**: reason 入力（Critical 時は必須、通常は任意） → スキップ記録
- **d**: reason 入力任意、defer_until 入力 → スキップ記録
- **D**: diff 表示後に再選択

PJ-protected files（CLAUDE.md / README* / .gitignore）が個別判断に来た場合は、`a` 選択後も Step 6 の blind overwrite ではなく Step 6.4 の merge 経路に入る。

### Step 6: 適用実行 + SIDEKICK_VERSION 更新 + Critical フラグ削除

選択が完了したら、一括適用実行。**PJ-protected files（CLAUDE.md / README* / .gitignore）はこのステップで上書きしない**（Step 6.4 で扱う）。

```bash
# blind overwrite から PJ-protected files を除外
PROTECTED='^(CLAUDE\.md|README\.md|README\.ja\.md|\.gitignore)$'

for f in $APPLIED_FILES; do
  if echo "$f" | grep -qE "$PROTECTED"; then
    PROTECTED_PENDING+=("$f")  # Step 6.4 で扱う
    continue
  fi
  git show "${LATEST}:$f" > "$f"  # タグ参照（drift 回避）
done

# SIDEKICK_VERSION を最新に（CLAUDE.md は単一行 sed なので safe）
sed -i 's/^SIDEKICK_VERSION: .*/SIDEKICK_VERSION: "'"${LATEST#v}"'"/' CLAUDE.md

# Critical 未取込フラグの削除（ADR-0009 P3、検知層の解除）
if [ "$SEVERITY" = "Critical" ]; then
  FLAG="$HOME/.claude/projects/$(pwd | sed 's|/|-|g')/memory/project_critical_pending.md"
  [ -f "$FLAG" ] && rm "$FLAG" && echo "Critical フラグをクリアしました（session-start.sh の warning は停止）"
fi
```

### Step 6.4: CLAUDE.md migration（PJ-protected の安全な取り込み）

`PROTECTED_PENDING` に積まれた PJ-protected files を、PJ 固有値を保持したまま新リリースの構造に追従させる。

#### 6.4a: CLAUDE.md — Project Configuration の新フィールド追加

新リリースで Project Configuration に追加されたフィールドを、既存値を壊さずに append する:

```bash
# 新リリースの Project Configuration ブロックを取得
NEW_CFG=$(git show "${LATEST}:CLAUDE.md" | awk '/^```yaml$/,/^```$/')

# フィールド名の一覧
ALL_FIELDS=$(echo "$NEW_CFG" | grep -oE '^[A-Z_][A-Z_0-9]*:' | sort -u)

# 現在の CLAUDE.md にないフィールド名を heredoc 経由で抽出（メインシェル内ループ）
NEW_FIELDS=()
while IFS= read -r field; do
  [ -z "$field" ] && continue
  grep -q "^${field}" CLAUDE.md || NEW_FIELDS+=("$field")
done <<< "$ALL_FIELDS"

if [ ${#NEW_FIELDS[@]} -gt 0 ]; then
  echo "新規 Project Configuration フィールド検出:"
  printf '  - %s\n' "${NEW_FIELDS[@]}"
  echo ""
  echo "既存 CLAUDE.md の Project Configuration ブロック末尾に追加してよいか? [Y/n]"
  # Y なら、各 NEW_FIELD のデフォルト行（コメント含む）を $NEW_CFG から抜き出して追記
fi
```

**ループ実装の注意**: `... | sort -u | while read field; do ...` のパイプ経由ループは bash の subshell 仕様で 1 イテレーションで停止する事象が観測された（dogfood 検証）。**heredoc (`<<<`) 経由でメインシェル内に入力**するパターンに統一する。配列収集 (`NEW_FIELDS+=("$field")`) も heredoc 形式なら問題なく動作する。

**判断基準**: 新フィールドはデフォルト値で追加。既存フィールドの値は触らない。

#### 6.4b: CLAUDE.md — brain `@import` 接続の確認

下流 PJ の CLAUDE.md が PJ brain にリンクしていない場合、2 層構造はファイル配置されても inert になる:

```bash
if ! grep -q '@\.claude/brain/thinking\.md' CLAUDE.md; then
  echo "⚠️  CLAUDE.md に PJ brain への @import がありません。"
  echo "   2 層 brain 構造（ADR-0016）を有効にするには、CLAUDE.md の §1 か任意の場所に以下を追加:"
  echo "       @.claude/brain/thinking.md"
  echo ""
  echo "   PJ brain が `@~/.claude/brain/thinking.md` で個人 brain を transitive import する 1 段構造。"
  echo "   下流 PJ の §1 が「プロジェクト概要」等で独自の場合、別セクション（例: §1.5 判断基盤）として追加可。"
  echo "   自動挿入する? [y/N]"
  # y なら CLAUDE.md の最後（## 3 等の前）に挿入。N なら案内のみ
fi
```

**自動挿入を default `N` にする理由**: PJ ごとに §構成が違うため、機械挿入は誤配置を生む。手動で適切な位置を決めるほうが安全。

#### 6.4c: README.md / README.ja.md / .gitignore

これらは下流 PJ ごとに完全独自。**自動上書きしない**。差分を案内するのみ:

```bash
for f in README.md README.ja.md .gitignore; do
  if echo "$PROTECTED_PENDING" | grep -q "^${f}$"; then
    echo "ℹ️  ${f} は sidekick で更新があるが、PJ 固有のため自動取り込みしない:"
    git diff "v${CURRENT}..${LATEST}" -- "$f" | head -20
    echo "   必要な部分だけ手動で取り込んでください。"
  fi
done
```

#### 6.4d: docs/decisions/（ADR 全体）— 取り込み対象外 + 残骸自動清掃

sidekick の ADR は sidekick 自身の設計判断記録であり、下流 PJ の判断空間とは独立している（ADR-0014）。`/adopt-sidekick-update` は ADR ファイルを下流に配布しない。

加えて、ADR-0014 適用前に下流 PJ に取り込まれた sidekick 由来 ADR ファイルを自動検知し、ユーザー確認の上で削除する（ADR-0015 の自動清掃）。

```bash
# Step 6.4d-1: ccs リモートから sidekick 側 ADR ファイル名一覧を取得
SIDEKICK_ADRS=$(git ls-tree -r --name-only ccs/main -- 'docs/decisions/' 2>/dev/null \
  | grep -E '^docs/decisions/.*\.md$' \
  | grep -v '/README\.md$' \
  | grep -v '/_template\.md$' \
  | sort -u)

# Step 6.4d-2: 下流 PJ 内の同名ファイルを検出し、内容完全一致のものだけ残骸候補にする
STALE_CANDIDATES=()
for adr in $SIDEKICK_ADRS; do
  [ -f "$adr" ] || continue
  # 内容完全一致確認（PJ 固有 ADR と偶然同名のリスクを回避）
  if diff -q "$adr" <(git show "ccs/main:$adr") >/dev/null 2>&1; then
    STALE_CANDIDATES+=("$adr")
  fi
done

# Step 6.4d-3: ADR_NOTICE 表示
if [ -n "$ADR_NOTICE" ]; then
  echo "ℹ️  sidekick 側で ADR が更新されています（取り込み対象外、ADR-0014）:"
  echo "$ADR_NOTICE" | sed 's/^/    /'
  echo "    詳細はリリースノート / sidekick リポの docs/decisions/ を参照してください。"
fi

# Step 6.4d-4: 残骸の自動清掃提案（ADR-0015）
if [ ${#STALE_CANDIDATES[@]} -gt 0 ]; then
  echo ""
  echo "🧹 過去取り込みによる sidekick 由来 ADR 残骸を検知しました（ADR-0015 自動清掃）:"
  printf '    - %s\n' "${STALE_CANDIDATES[@]}"
  echo ""
  echo "    これらは下流 PJ にとって不要なノイズです（ADR-0014 で配布廃止済み）。"
  echo "    [Y]全削除（推奨） / [n]個別判断 / [s]残す"
  read -r CLEANUP_CHOICE
  CLEANUP_CHOICE=${CLEANUP_CHOICE:-Y}

  case "$CLEANUP_CHOICE" in
    Y|y)
      for f in "${STALE_CANDIDATES[@]}"; do
        rm "$f" && echo "  削除: $f"
      done
      # docs/decisions/README.md の索引から削除済 ADR の行を除去
      if [ -f docs/decisions/README.md ]; then
        for f in "${STALE_CANDIDATES[@]}"; do
          base=$(basename "$f")
          # ファイル名を含む行を sed で削除（リンク記法 / 表エントリの両方に対応）
          sed -i.bak "/${base//./\\.}/d" docs/decisions/README.md && rm -f docs/decisions/README.md.bak
        done
        echo "  索引更新: docs/decisions/README.md"
      fi
      ;;
    n)
      for f in "${STALE_CANDIDATES[@]}"; do
        echo "  $f を削除しますか? [Y/n]"
        read -r CHOICE
        if [ "${CHOICE:-Y}" = "Y" ] || [ "${CHOICE:-Y}" = "y" ]; then
          rm "$f" && echo "    削除"
          if [ -f docs/decisions/README.md ]; then
            base=$(basename "$f")
            sed -i.bak "/${base//./\\.}/d" docs/decisions/README.md && rm -f docs/decisions/README.md.bak
          fi
        fi
      done
      ;;
    s)
      echo "  残骸を保持します（次回の取り込みで再提示）"
      ;;
  esac
fi
```

**識別ロジック**: `git ls-tree ccs/main -- docs/decisions/` で sidekick 側 ADR ファイル名一覧を取得し、下流 PJ 内の同名ファイルとの**ファイル内容を完全比較**する。完全一致したものだけを残骸として確定する。これにより、PJ 固有 ADR が偶然同じ番号 / ファイル名を持つ場合でも誤削除を防ぐ（内容が異なれば候補から除外）。

**前提**: `/inventory` が事前に実行され `git fetch ccs` 済みであること（`ccs/main` 参照が必要）。

**仕様の根拠を確認したい場合**: rules / brain / CHANGELOG が一次情報源。それでも判断経緯を追いたい場合のみ sidekick リポの ADR を直接参照する。下流 PJ の `docs/decisions/` は下流自身の領域として完全独立。

### Step 6.5: 個人 brain の取り扱い（ADR-0016、2 層 brain モデル）

OSS テンプレート（`brain/thinking.md`）に変更があった場合、または利用者の個人 brain（`~/.claude/brain/thinking.md`）が未配置の場合に、案内を出す。

**個人 brain は絶対に自動上書きしない**。利用者が育てた判断軸を失う事故を防ぐ（ADR-0016）。

```bash
PERSONAL_BRAIN="$HOME/.claude/brain/thinking.md"
# テンプレート変更検知は Step 2 の BRAIN 変数（git diff 結果）を使う。
# APPLIED_FILES（適用済みのみ）を使うと、利用者が [brain] 全スキップした場合に
# 差分提案が発火しないため不適切。
TEMPLATE_CHANGED=$(printf '%s\n' "$BRAIN" | grep -q '^brain/thinking\.md$' && echo "yes" || echo "no")

# (1) 個人 brain 未配置時: 初期化を提案
if [ ! -f "$PERSONAL_BRAIN" ]; then
  echo ""
  echo "ℹ️  個人 brain が未配置: $PERSONAL_BRAIN"
  echo "   OSS テンプレート (brain/thinking.md) から初期化しますか? [Y/n]"
  read -r CHOICE
  if [ "${CHOICE:-Y}" = "Y" ] || [ "${CHOICE:-Y}" = "y" ]; then
    mkdir -p "$(dirname "$PERSONAL_BRAIN")"
    git show "${LATEST}:brain/thinking.md" > "$PERSONAL_BRAIN"
    echo "個人 brain を初期化しました（今後は利用者が育てる、自動上書きしない）"
  else
    echo "スキップ（後で /setup または再実行で初期化可能）"
  fi

# (2) 個人 brain 既存 + テンプレート変更あり: 差分提案のみ（自動上書き禁止）
elif [ "$TEMPLATE_CHANGED" = "yes" ]; then
  echo ""
  echo "📝 OSS テンプレートに更新があります。個人 brain との差分を表示:"
  diff "$PERSONAL_BRAIN" <(git show "${LATEST}:brain/thinking.md") | head -60
  echo ""
  echo "個人 brain は自動上書きしません（ADR-0016「上書き禁止運用」）。"
  echo "必要な部分だけ手動で取り込んでください: $PERSONAL_BRAIN"
  echo '  比較コマンド例: diff "$HOME/.claude/brain/thinking.md" <(git show "'"${LATEST}"':brain/thinking.md")'

# (3) その他: 何もしない
fi
```

判断基準:
- **OSS テンプレートはリポ内ファイル**: ロード対象外。`brain/` カテゴリで blind overwrite される（PJ ローカルファイルとして）が、利用者の context には影響しない
- **個人 brain は利用者領域**: `/setup` 初回 or `/adopt-sidekick-update` での明示的同意でのみ初期化。以降は触らない
- **差分マージは手動**: 利用者の判断軸との衝突を機械では判定できない

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
- **個人 brain は絶対上書きしない**: Step 6.5 で `~/.claude/brain/thinking.md` を自動更新しない。育てた判断軸を失う事故を防ぐ（ADR-0016）。不在時のみ初期化を提案、存在時は差分提案のみ
- **OSS テンプレートはリポ内のみ**: `brain/thinking.md` は配布素材としてリポ内に配置されるが、ロード対象外。利用者が育てるのは個人 brain のみ
- **Step 6.5 / 6.4d の `read` は対話前提**: `--all` 等の auto モード対応は本スキル全体の課題。本 Step だけ対応すると整合崩れ。auto モードでは Step 6.5 (1) の初期化プロンプトと Step 6.4d の cleanup プロンプトでハングし得る点に注意（auto 化は別タスク）
- **PJ-protected files の blind overwrite 禁止**: `CLAUDE.md` `README*` `.gitignore` は Step 6 で上書きしない（Step 6.4 で扱う）。下流 PJ の Project Configuration 値や独自 README が消える事故を防ぐ
- **brain @import の手動接続**: Step 6.4b で CLAUDE.md に `@.claude/brain/thinking.md` を自動挿入しないのが default。PJ ごとに §構成が違うため、誤配置を生む。手動位置決め推奨
- **タグ参照（ドリフト回避）**: `git show` の対象は `${LATEST}` タグ（リリース時点固定）。`ccs/main` を使うと post-release commit が混ざる可能性あり
- **SIDEKICK_VERSION 抽出のクォート**: シングル/ダブルクォート両対応の regex を Step 0 で使う。下流 PJ で書式が揺れていても CURRENT を正しく抽出する
- **`while read` は heredoc で**: パイプ経由 (`... | while read; do ...; done`) はサブシェル化により 1 イテレーション後に停止する事象あり。`done <<< "$VAR"` のヒアストリング形式を使うと配列収集も含めて確実に動く

## 参考

- ADR-0009: リリース取り込み設計
- `references/skip-record-format.md`: スキップ記録フォーマット詳細
- `/inventory`: Critical 検知 + 1行サマリ（軽量）
- `/weekly-inventory`: 全 severity 含む深い棚卸し
- `/release`: リリース発信側（sidekick 保守者）
- `/setup`: ccs remote 初期設定
