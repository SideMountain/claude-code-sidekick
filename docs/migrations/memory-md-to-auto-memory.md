# 移行ガイド: project-root MEMORY.md → auto-memory 一本化

**対象**: sidekick v0.5.0 以降を取り込む既存下流 PJ

**背景**: ADR-0008 により、project-root の `/MEMORY.md` を廃止し、Claude Code 標準の auto-memory システム（`~/.claude/projects/<project-slug>/memory/`）に一本化しました。

本ガイドは既存下流 PJ が新しい構成に移行する手順を示します。

---

## 移行の要否判定

以下のいずれかに該当する場合は移行が必要です:

- [ ] project root に `/MEMORY.md` が存在する
- [ ] `/MEMORY.md` に `<!-- sidekick_version: x.x.x -->` コメントがある
- [ ] `/MEMORY.md` に Active Work / Backlog を記載している

該当しない場合、移行は不要です。sidekick を更新してそのまま使えます。

---

## 移行手順

### Step 1: 現在の /MEMORY.md の内容を分類

`/MEMORY.md` のセクションごとに、以下のカテゴリに分類:

| セクション例 | 移行先 |
|---|---|
| `## Active Work` | auto-memory MEMORY.md |
| `## Backlog` | auto-memory MEMORY.md or GitHub Issues |
| `## Project Overview` / `## Milestones` | `CLAUDE.md` 新規セクション or `docs/` 配下 |
| `## Critical Rules` | 既に CLAUDE.md にある内容なら削除、新規情報なら CLAUDE.md へ統合 |
| `## File Roles` | 削除（CLAUDE.md / rules/documentation.md で定義済み） |
| `## Owner's Thinking OS` | `.claude/rules/thinking.md` §1 へ統合 |
| `## Feedback` | auto-memory `feedback_*.md` へ（Claude が自動で作る） |
| `<!-- sidekick_version: x.x.x -->` | `CLAUDE.md` の `SIDEKICK_VERSION` へ |
| `## Memory Index` | auto-memory MEMORY.md の索引セクションへ |

### Step 2: auto-memory MEMORY.md を作成

`~/.claude/projects/<project-slug>/memory/MEMORY.md` を作成。`<project-slug>` はプロジェクトパスをハイフン区切りにしたもの（例: `/mnt/c/Users/xxx/repos/myproj` → `-mnt-c-Users-xxx-repos-myproj`）。

テンプレート:

```markdown
# MEMORY.md

## Active Work

| ブランチ | Worktree | 作業内容 | 影響範囲 | DB Migration | Status |
|---|---|---|---|---|---|

## Backlog

（必要に応じて旧 /MEMORY.md から移植）

## Memory Index

<!-- feedback_*.md / reference_*.md 等がこの配下に生成されたら索引する -->

<!-- 最終棚卸し: YYYY-MM-DD -->
```

### Step 3: CLAUDE.md に SIDEKICK_VERSION を追加

CLAUDE.md 冒頭の Project Configuration YAML ブロックに追記:

```yaml
SIDEKICK_VERSION: "0.5.0"   # 旧 MEMORY.md の <!-- sidekick_version --> の値
```

### Step 4: Project Overview / Milestones の移管

もし旧 `/MEMORY.md` にプロジェクト概要やマイルストーン表があった場合:

**選択肢 A**: CLAUDE.md に新セクションを追加

```markdown
## プロジェクト概要

（旧 MEMORY.md の Project Overview セクションをここへ）

## マイルストーン

（同様）
```

**選択肢 B**: `docs/PROJECT_OVERVIEW.md` を新規作成して移管

大量の情報がある場合や、要件定義書 URL 等が含まれる場合は B 推奨。

### Step 5: 旧ファイルの削除

```bash
rm MEMORY.md
```

`.gitignore` から `/MEMORY.md` エントリも削除（このエントリは新 `.gitignore` template にありません）。

### Step 6: 動作確認

次セッション開始時、session-start hook が Active Work を正しく読めるか確認:

```
[3/5] Active Work (parallel work board)
  | ブランチ | Worktree | 作業内容 | ... |  ← テーブル表示されれば OK
```

`/inventory` で SIDEKICK_VERSION が正しく読まれるか確認:

```
[sidekick] v0.5.0 （最新: vX.X.X）
```

---

## よくある質問

### Q. Active Work や Backlog を auto-memory に置くと、チームで共有できなくなる？

A. 元々 `/MEMORY.md` も gitignored で個人ローカル扱いでした。チーム共有が必要な情報（Milestones 等）は CLAUDE.md や `docs/` に置くべきで、auto-memory は個人の作業メモです。

### Q. 既に auto-memory に何か入っていたが、そこに追記していいのか？

A. 問題ありません。auto-memory は Claude Code が自動管理するので、既存ファイルと混在しても機能します。

### Q. `/MEMORY.md` を残したまま併用していいか？

A. 併用は推奨しません。どちらに書くか迷う原因になります。廃止して auto-memory に一本化してください（ADR-0008 参照）。

### Q. このガイドに従うと sidekick 側の /setup や /close-chat は再配置されるか？

A. されません。`/setup` は既存 PJ モードで `MEMORY.md` を配置しなくなりますが、既存ファイルは残ります。ユーザー側で手動削除が必要です。

---

## 参考

- ADR-0008: project-root MEMORY.md を廃止し auto-memory に一本化
- `.claude/rules/documentation.md`: ドキュメントレイヤーの使い分け
- `.claude/rules/knowledge-map.md`: 知識の配置先マップ
