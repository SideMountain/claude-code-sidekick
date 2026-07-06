# Skip Record Format Specification

`/adopt-sidekick-update` スキルが `auto-memory/project_skipped_updates.md` に記録する
スキップ項目のフォーマット詳細。

---

## ファイル配置

`~/.claude/projects/<project-slug>/memory/project_skipped_updates.md`

auto-memory ディレクトリ配下。Claude Code 標準の個人ローカル領域。
git 管理外（ADR-0005「既存PJ非侵襲」原則に従う）。

---

## スキーマ

```markdown
# Skipped sidekick updates

## 永久スキップ

- path: `.claude/rules/deploy-strategy.md`
  reason: デプロイ対象を持たない PJ（ローカルツールのみ）のため不要
  since: 2026-04-18
  skipped_version: v0.5.0

- path: `.claude/rules/database.md`
  reason: DB を使わない PJ
  since: 2026-04-18
  skipped_version: v0.5.0

## 後回し

- path: `docs/migrations/memory-md-to-auto-memory.md`
  reason: 移行作業の時間がない
  defer_until: 2026-05-01
  deferred_version: v0.5.0
```

---

## フィールド定義

### 永久スキップ項目

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `path` | string | ✅ | 対象ファイルのプロジェクトルートからの相対パス |
| `reason` | string | ✅（Critical時）/ 推奨（通常） | スキップの理由 |
| `since` | date (YYYY-MM-DD) | ✅ | スキップ開始日 |
| `skipped_version` | version tag | ✅ | スキップした時点の sidekick バージョン |

### 後回し項目

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `path` | string | ✅ | 対象ファイルのプロジェクトルートからの相対パス |
| `reason` | string | 推奨 | 後回しの理由 |
| `defer_until` | date (YYYY-MM-DD) | 任意 | 再提示してほしい日付 |
| `deferred_version` | version tag | ✅ | 後回しした時点の sidekick バージョン |

---

## 再提示ロジック

### 永久スキップ

- `/inventory` および `/adopt-sidekick-update` で**表示しない**（対象外）
- ただし `/weekly-inventory` では全永久スキップを棚卸し対象として一覧表示
  - PJ の性質変化（UI 追加等）があれば見直しを提案

### 後回し

以下のいずれかの条件で再提示:

1. `defer_until` が現在日付以前になった
2. `defer_until` が未設定なら、次回 `/inventory` 実行時に再提示
3. 新しいリリースが出た（`deferred_version` より新しい Release が発行された）

再提示時は先頭に「前回スキップ（reason: ..., defer_until: ...）」と表示する。

---

## 棚卸し（/weekly-inventory 連携）

`/weekly-inventory` で以下をレポート:

- 永久スキップの総数
- 後回しで `defer_until` を過ぎているのに未対応の項目
- 永久スキップで PJ 性質変化に伴い見直しが推奨される項目

棚卸しで整理された項目は、直接編集してユーザーが手動削除する（永久スキップから外す等）。

---

## 整合性チェック

### 適用時（Step 5 で a を選択）

- path が既に「永久スキップ」に含まれる場合、警告「既に永久スキップ指定あり。削除しますか？」
- path が既に「後回し」に含まれる場合、該当エントリを自動削除（適用したので不要）

### スキップ追加時（Step 5 で s/d を選択）

- path が既に永久/後回しに含まれる場合、エントリを更新（reason/since/defer_until 等を最新化）

### 永久 ↔ 後回しの切替

- 後回し項目を永久スキップに変更するケース: reason 必須、`since` を今日に設定
- 永久項目を後回しに戻すケース: 稀。`/weekly-inventory` で手動編集を推奨

---

## 設計意図

1. **個人ローカル**: チームメンバー間でスキップ判断が異なる可能性があるため、git 管理外に置く
2. **Claude 管理**: auto-memory の慣行に従い、Claude Code が自動メンテする
3. **棚卸し可能**: `/weekly-inventory` が定期的に見直しを提案し、肥大化を防ぐ
4. **バージョン紐付け**: `skipped_version` / `deferred_version` で「いつスキップしたか」を追跡、後から PJ 性質変化を判断できる
