# Changelog

sidekick のリリース履歴。セマンティックバージョニングに従う。

各PJは MEMORY.md の `sidekick_version` で取り込み済みバージョンを管理し、
`/inventory` で未適用の更新を検知する。

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
