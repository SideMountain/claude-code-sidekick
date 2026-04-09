# Changelog

sidekick のリリース履歴。セマンティックバージョニングに従う。
バージョンは git tag + GitHub Releases で管理する。

各PJは MEMORY.md の `sidekick_version` で取り込み済みバージョンを管理し、
`/inventory` で GitHub Releases API 経由で未適用の更新を検知する。

## [0.4.0] - 2026-04-09

### Added
- `/setup` に既存PJモードを追加（CLAUDE.md が既にある場合の非侵襲的セットアップ）
- `.claude/templates/` ディレクトリ（MEMORY.md, CLAUDE.local.md, GitHub テンプレート）
- `.claude/docs/` ディレクトリ（毎セッション読み込まない開発者リファレンス）
- `/auto-implement` に推奨ユースケースセクション（テスト追加から始める段階的導入ガイド）
- ADR-0005: 下流統合設計原則（.claude/ 封じ込め、opt-in 配置、既存PJ非侵襲）

### Changed
- バージョン管理を VERSION ファイル → git tag + GitHub Releases に移行
- `/inventory` のバージョンチェックが GitHub Releases API を使用
- `/setup` の .gitignore 追記がファイル配置と連動（配置しなかったファイルのパターンは追記しない）
- `skill-agent-design.md` を `rules/` → `.claude/docs/` に移動（コンテキスト常駐の解消）
- `mcp-recommendations.md` を `rules/` → `skills/setup/references/` に移動（/setup 時のみ参照）
- `MEMORY.md.example` → `.claude/templates/MEMORY.md` に移動
- `CLAUDE.local.md.example` → `.claude/templates/CLAUDE.local.md` に移動
- `.github/` テンプレートの下流向けコピーを `.claude/templates/github/` に分離
- `.gitignore` のコメント構造を整理（コア/配置依存/PJ固有の区分）

### Removed
- ルートの `VERSION` ファイル（git tag に移行）

## [0.3.0] - 2026-04-08

### Added
- `/review-design` スキル（UI/UX一貫性・デザインシステム・a11y）
- `/review-spec` スキル（API契約・仕様書乖離・破壊的変更）
- `/review` の動的スコープ判定で design/spec を自動選択
- Stop hook（設計判断のADR記録漏れを自動検出。再発火防止付き）
- guard-bash.sh Guard 8: PRマージ時のベースブランチ動的判定
- settings.json に deny[] セクション（禁止事項の可視化）
- テスト実行最適化ルール（ローカル=スコープ限定、main=フル）
- `/setup` Step 4: オーナー情報ヒアリング（テンプレ選択肢 + 全スキップ可）

### Changed
- `/weekly-review` に外部情報収集・hooks実績分析を統合（旧scout-process機能）
- thinking.md Step 4: 一貫性チェック対象を明示化（CLAUDE.md, thinking.md, ADR, feedback）

### Removed
- `/scout-process`（weekly-reviewに統合）
- `/scout-product`（テンプレートのまま使われにくいため削除）
- `/sync-to-notion`（Notion依存解消方針に伴い削除）

## [0.2.0] - 2026-04-07

### Added
- 外部タスク管理連携プロトコル（CLAUDE.md §9 + `.claude/rules/` で設定）
  - Tasks DB 同期、Sourceタグ、即時投入ルール
- ADR（Architecture Decision Records）体制
  - `docs/decisions/` + `/record-decision` スキル
  - ADR-0001〜0004: OSS配信、ブラックリスト方式、Slack連携、コンテキスト集約
- 知識の格納マップ（`.claude/rules/knowledge-map.md`）
- `/weekly-review` スキル（定期棚卸し）
- `/close-chat` に知識還流チェック（Step 2.5）を追加
- VERSION + CHANGELOG によるリリース管理

## [0.1.0] - 2026-04-06

### Added
- AI伴走開発ベーステンプレートの初版
  - CLAUDE.md: HARD/SOFT/GUIDE ルール体系
  - thinking.md: 判断基盤と行動プロトコル
  - hooks: guard-bash, guard-commit-message, guard-db-operation, guard-protected-branch-edit
  - skills: close-chat, news, record-decision, review (code/ops/test), setup, sync-to-notion
  - Worktree 運用プロトコル
  - Git Strategy（ブランチ戦略、PR作成ゲート、Merge Strategy）
- 運用プロジェクト実績からのバックポート
- public リポジトリでの固有名詞除外ルール
