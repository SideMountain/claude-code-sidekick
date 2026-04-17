# ADR-0001: バージョン管理と複数プロジェクトへの配信方式

## ステータス

改訂済み（2026-04-18）— git tag + GitHub Releases に移行（2026-04-09）。`sidekick_version` の置き場を project-root MEMORY.md → `CLAUDE.md` の `SIDEKICK_VERSION` へ移管（2026-04-18、ADR-0008）

## 背景

sidekick を複数プロジェクトで共有テンプレートとして使う場合、以下の課題がある:

1. テンプレートの更新を各プロジェクトに展開する仕組みがない
2. プロジェクト固有設定と汎用ルールが混在している
3. 既存プロジェクトへの後付け導入方法が未整備

## 検討内容

### 配信フロー

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| git remote で pull | 差分管理が正確 | コンフリクト管理の負担 |
| npm パッケージ化 | OSS 標準 | オーバーエンジニアリング |
| GitHub Template + Releases | 外部ユーザーに自然 | 既存PJの自動化に不向き |
| **/inventory で差分取り込み** | PJ側で自律的に取り込める | バージョン追跡の仕組みが必要 |

### バージョン管理方式（改訂時に追加）

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| ルートに VERSION ファイル | シンプル | 下流PJのルートを汚染する |
| **git tag + GitHub Releases** | OSS 標準。下流PJにファイル残さない | オフラインで確認不可 |
| package.json の version | npm 標準 | sidekick は npm パッケージではない |

## 決定

1. ~~VERSION + CHANGELOG を導入~~ → **git tag + GitHub Releases** でリリース管理する（改訂）
2. **`/inventory` スキルにバージョンチェックを組み込む**。`CLAUDE.md` の `SIDEKICK_VERSION` と GitHub Releases API を比較し、未適用の更新があれば差分を表示（ADR-0008 により MEMORY.md から移管）
3. **CLAUDE.md 構造分離は後回し**。`/inventory` の差分取り込みで代替する。PJ数が増えたら再検討
4. **PJ固有ファイルを .gitignore に追加**。テンプレートファイルは `.claude/templates/` に格納し、`/setup` が opt-in で配置する（改訂）
5. **スキルの階層構造を導入**（SKILL.md + references/ + agents/ + templates/ 構造）

## 理由

- `/inventory` に組み込む方式は「各PJの Claude Code が自律的に取り込む」横展開フローと一致
- git tag + GitHub Releases は OSS の標準慣行。VERSION ファイルは下流PJのルートを汚染する
- テンプレートファイルの `.claude/templates/` 格納は、下流PJのルート名前空間を保護する

## 影響

- 廃止: VERSION ファイル（ルート）
- 変更: CHANGELOG.md は sidekick upstream リポのみに存在（下流には伝播しない）
- 変更: `*.example` ファイル → `.claude/templates/` に移動
- 変更: `/inventory` のバージョンチェックが GitHub Releases API を使用
- 各PJの `CLAUDE.md` Project Configuration に `SIDEKICK_VERSION` フィールドを維持（ADR-0008 により MEMORY.md から移管）