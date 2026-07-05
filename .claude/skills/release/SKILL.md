---
name: release
description: "claude-code-sidekick（ccs）のリリース切り。温度感判定・機械的変更リスト生成・CHANGELOG bump・タグ作成・GitHub Release 作成までを対話型で一貫実行する。"
user-invocable: true
allowed-tools: "Read Edit Write Grep Glob Bash(git *) Bash(gh *)"
---

# /release — リリース切りスキル

## 目的

claude-code-sidekick（ccs）のリリースを **手順漏れなく**切る。特に以下を保証する:

- **思想漏洩防止**: リリースノートに「変更された ADR / rules」を機械的に列挙
- **温度感の明示**: Critical / Standard / Enhancement の3段階を title/body に明記
- **CHANGELOG bump の一貫性**: `[Unreleased]` → `[x.y.z]` の書式統一

ADR-0009 で定義した設計に準拠する。
**フォーマットの詳細仕様**は `references/release-format-spec.md` を参照（Step 6 で読み込む）。

## いつ使うか

- `[Unreleased]` に変更が溜まり、リリースとして切りたいとき（CHANGELOG bump + tag + GitHub Release 作成）
- 緊急バグ修正を hotfix リリースとして切るとき（Critical 温度感）

## いつ使わないか

- まだ変更が `[Unreleased]` に溜まっていない
- 未完了の PR が main にある（先にマージを待つ）

---

## 手順

### Step 0: 前提確認

```bash
git fetch origin
git branch --show-current  # main であること
git status                 # clean
git log HEAD..origin/main --oneline  # 未取り込みなし
head -30 CHANGELOG.md      # [Unreleased] に項目がある
```

未取り込みがあれば `git pull --ff-only origin main`。`[Unreleased]` が空ならリリース不要で終了。

### Step 1: 温度感の判定（対話）

ユーザーに Critical / Standard / Enhancement のどれかを確認する。
`references/release-format-spec.md` §「温度感の判定基準」の**判定手順（決定木）で判定する**（上から順に、最初に該当した severity を採る）。

迷ったら上位（Critical > Standard > Enhancement）を選ぶ。

### Step 2: バージョン判定（対話 + semver）

`git describe --tags --abbrev=0` で最新タグ取得。semver で次を提案:

| 含む変更 | 推奨 bump |
|---|---|
| Breaking Changes あり | minor（pre-1.0）/ major（post-1.0） |
| Added / Changed のみ | minor |
| Fixed のみ | patch |

ユーザー確認後に決定。

### Step 3: 機械的変更リスト生成（**本スキルの要**）

前回タグ以降の変更を機械抽出する:

```bash
# タグ取得（タグ無しのリポは初回リリース扱いで fallback）
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
if [ -z "$LAST_TAG" ]; then
  LAST_TAG=$(git rev-list --max-parents=0 HEAD | tail -1)
  echo "注: タグなし → 最初のコミット ($LAST_TAG) からの全変更を対象にする"
fi
RANGE="${LAST_TAG}..HEAD"

# 変更された ADR（新規/改訂）— git diff を使うことで commit メッセージが混ざらない
git diff --name-only --diff-filter=AM "$RANGE" -- 'docs/decisions/*.md' | sort -u

# 変更された rules
git diff --name-only --diff-filter=AM "$RANGE" -- '.claude/rules/*.md' | sort -u

# 変更された skills（SKILL.md 本体 + references/ + 決定的検査の scripts/ + templates/）
git diff --name-only --diff-filter=AM "$RANGE" -- '.claude/skills/' | grep 'SKILL.md$\|references/\|scripts/\|templates/' | sort -u

# 変更された hooks（強制層・Critical 修正の配布経路）と共有スクリプト
git diff --name-only --diff-filter=AM "$RANGE" -- '.claude/hooks/' '.claude/githooks/' '.claude/scripts/' | sort -u

# 変更された遅延ロード doc（rules 参照先の単一ソース）
git diff --name-only --diff-filter=AM "$RANGE" -- '.claude/docs/*.md' | sort -u

# マージされた PR（コミット履歴が欲しいため git log のまま）
git log "$RANGE" --merges --oneline
```

各ファイルを **新規 (A) / 改訂 (M) / 削除 (D)** で区別する。削除ファイルは別途取得:

```bash
git diff --name-only --diff-filter=D "$RANGE" -- 'docs/decisions/*.md' '.claude/rules/*.md' '.claude/skills/'
```

この結果が Step 6 の「変更された…」セクションの素材になる。

### Step 4: CHANGELOG 更新

`Edit` ツールで `[Unreleased]` セクションの内容を `[X.Y.Z] - YYYY-MM-DD` にリネーム。
新しい空の `[Unreleased]` placeholder を上に追加する。

### Step 5: Worktree → コミット → PR（要承認）

```bash
git worktree add ../<repo>-release-vX.Y.Z -b release/vX.Y.Z origin/main
# auto-memory MEMORY.md Active Work に記録（H13）
cd ../<repo>-release-vX.Y.Z
# CHANGELOG.md は Step 4 で既に更新済み → そのまま
git add CHANGELOG.md
git commit -m "chore: CHANGELOG X.Y.Z リリース切り"
git push -u origin release/vX.Y.Z  # 要ユーザー確認
gh pr create ...  # 要ユーザー確認
```

PR 本文には Step 3 の機械リストを含める。

### Step 6: マージ後 — tag + GitHub Release 作成

ユーザーが PR をマージしたら:

```bash
git pull --ff-only origin main
git tag -a vX.Y.Z -m "vX.Y.Z — {要約}"
git push origin vX.Y.Z  # 要ユーザー確認
```

**GitHub Release 作成** — ここが本スキルの核心。**必ず `references/release-format-spec.md` を Read** してフォーマットを確認する:

- severity マーカー行（`> severity: critical|standard|enhancement`、body 最冒頭）— `/inventory`・`/adopt-sidekick-update` が機械検知に使う第一ソース。title prefix・banner と必ず一致させる
- Title prefix（Critical / Standard / Enhancement 別）
- Body banner（severity 別の文言）
- 必須セクション（Highlights、Changes、変更された ADR、変更された rules、変更された skills、Full Changelog）

```bash
gh release create vX.Y.Z --repo {owner}/{repo} --title "{title}" --notes "{body}"  # 要ユーザー確認
```

### Step 7: 完了記録

- auto-memory MEMORY.md の Active Work を「完了」に更新
- Worktree 削除（ユーザー明言後）

---

## Gotchas

- **`[Unreleased]` を空のまま残さない**: 必ず次リリース用の placeholder を残す（CHANGELOG 書式一貫性）
- **機械リストを人間記述で上書きしない**: Step 3 生成物（`## 変更された ADR` 等）は削除・編集しない。人間の記述は Highlights セクションで
- **Critical の即時性**: Critical は単独で切る。「Critical + 新機能」の batch は避ける
- **タグ push のタイミング**: PR マージ **後** にタグを打つ。マージ前のタグは branch 側を指してしまう
- **対話型スキルなので Agent 委譲しない**: ユーザー判断が多数挟まるため、メインコンテキストで実行する（skill-agent-design.md §2 参照）

## 参考

- ADR-0009: リリース取り込み設計
- ADR-0001: 配信方式（/inventory + GitHub Releases）
- `references/release-format-spec.md`: Title / Body / Banner 仕様の詳細
