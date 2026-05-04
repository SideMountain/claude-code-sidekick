# Changelog

sidekick のリリース履歴。セマンティックバージョニングに従う。
バージョンは git tag + GitHub Releases で管理する。

各PJは `CLAUDE.md` Project Configuration の `SIDEKICK_VERSION` で取り込み済みバージョンを管理し、
`/inventory` で GitHub Releases API 経由で未適用の更新を検知する。

## リリース温度感

各リリースは3段階の温度感に分類される（ADR-0009）:

- **[CRITICAL]** (`⚠️`): セキュリティ / 致命的バグ修正。即取り込み推奨
- **(No prefix)**: Standard — 通常の機能追加・修正（デフォルト）
- **[ENHANCEMENT]** (`💡`): opt-in な改善。後回し可

GitHub Release の title prefix と body 冒頭 banner に明示される。
`/release` スキルが切る時に判定する。

## [Unreleased]

## [0.7.1] - 2026-05-04

### Fixed

`/adopt-sidekick-update` の dogfood で発見した 6 件の bug を修正。下流 PJ が新リリースを取り込む際の安全性を向上。

- **CLAUDE.md / README\* / .gitignore の盲目的上書きを停止** (Step 6): PJ-protected files は専用の migration step (Step 6.4) で扱う。Project Configuration 値や PJ 独自 README が消える事故を防ぐ
- **SIDEKICK_VERSION 抽出 regex をシングル/ダブルクォート両対応に** (Step 0): 書式揺れに耐性を持たせる
- **`[PJ migration]` カテゴリのデフォルトを `[n]個別判断` に** (Step 4): PJ 固有内容を含むカテゴリは安全側に倒す
- **CLAUDE.md migration step 新設** (Step 6.4): (a) Project Configuration の新フィールドを既存値を壊さず append (b) brain `@import` 接続の確認と案内 (c) README\* / .gitignore は差分案内のみ
- **タグ参照化** (Step 5/6/6.5): `git show ${LATEST}:<path>` (リリース時点固定) に変更し、post-release commit との drift を回避

### Changed

- カテゴリを 5 種に再編成: `[ADR]` / `[rules]` / `[skills]` / `[brain]` / `[PJ migration]`

## [0.7.0] - 2026-05-02

### Added
- **brain 3 層構造**（ADR-0013）: 思考OS の格納先を「業界共通 (L0) / 個人 (L1) / PJ 固有 (L2)」の 3 スコープに分離。各層は `@import` でチェーン化（L2 → L1 → L0）
  - 新規 `brain/thinking.md` (L0 マスター、OSS 配布物として業界共通の判断軸を保持)
  - 新規 `.claude/brain/thinking.md` (L2 テンプレ、PJ 固有判断軸の置き場)
  - CLAUDE.md §1 を brain への参照に縮約。PJ 固有判断軸は L2 へ
- **個人情報・固有名詞の混入防止ルール**（HARD グレード、新規 `.claude/rules/pii-prevention.md`）: Notion ID/URL・内部 URL・接続情報のパターンと `scan_pii` 関数を提供。`/record-decision` `/close-chat` でセルフレビューを自動実行
- **Notion 判断ログ同期**（ADR-0012、opt-in）: 設計判断・方針判断を Notion 判断ログDB に蓄積する機能。`NOTION_JUDGMENT_SYNC` 独立フラグで `NOTION_ENABLED` と疎結合に制御
- ADR-0010: 思考OS の 2 層構造と配布・還流メカニズム（一部 Superseded by ADR-0013）
- `/setup` Step 4.5: brain 3 層配置パターン（物理コピー / L1 import のみ / 3 層 chain 推奨）の選択肢
- `/adopt-sidekick-update` Step 6.5: ホーム L0 (`~/.claude/ccs/brain/thinking.md`) の自動展開 + L1 案内
- `/record-decision` Step 5: ADR ドラフト完成後の PII セルフレビュー
- `/close-chat` Step 5.6: 公開ファイル変更時の PII セルフレビュー
- `/close-chat` Step 6.5: Notion 判断ログDB 同期（`NOTION_JUDGMENT_SYNC=true` の場合のみ）
- `CLAUDE.md` Project Configuration に `NOTION_JUDGMENT_SYNC` / `NOTION_JUDGMENT_DB_URL` を追加（デフォルト false）
- `.claude/rules/task-management.md` に「判断ログ同期」セクション（Notion 判断ログDB スキーマ定義含む）

### Changed
- `.claude/rules/code-quality.md`: 抽象的判断原則の参照先を thinking.md → brain L0 に更新
- `.claude/rules/knowledge-map.md`: 格納レイヤー表に L0/L1/L2 を反映、判断フロー・昇格ルール（PJ 内 → L2、別 PJ 観測 → L1、業界共通 → L0）を更新
- 還流タグを 3 層化: `[ベース昇格]` `[思考OS還流]` `[固有]` → `[L0候補]` `[L1候補]` `[L2固有]`（`/close-chat` `/weekly-inventory` の references 含む）
- README / README.ja の Quick Start 例を `--private --clone` 付きに更新（個人開発のフォーク手順を改善）

### Renamed
- `.claude/rules/thinking.md` → `brain/thinking.md`（思考OS を L0 として独立。`@import` で参照）

## [0.6.0] - 2026-04-18

### Added
- `/release` スキル新規（リリース発信側。温度感判定 + 機械的変更リスト生成 + CHANGELOG bump + tag + GitHub Release 作成）
- `/adopt-sidekick-update` スキル新規（下流 PJ の取り込み対話、カテゴリ一括 UX、スキップ永久/後回し記録）
- ADR-0009: リリース取り込み設計（温度感・思想漏洩防止・スキップ制御。P1+P2+P3 全実装）
- `/inventory` に Release severity 判定追加（Critical のみ強調、Standard/Enhancement は 1行サマリ）
- `/inventory` が Critical 検知時に auto-memory フラグファイル作成
- `/weekly-inventory` Step 0.5 追加（sidekick 未取込更新の棚卸し、全 severity、経過日数警告）
- `/setup` に ccs remote 自動追加ステップ
- `session-start.sh` に `[6/6] Critical sidekick update` セクション（未取込 Critical 警告の継続表示）
- `/adopt-sidekick-update` の Step 6 で Critical フラグをクリア

### Changed
- **`/weekly-review` → `/weekly-inventory` へ rename**（実態は棚卸し系のため `/inventory` との命名整合）
- CHANGELOG intro にリリース温度感セクション追加
- 関連ドキュメントの `/weekly-review` 参照を更新

## [0.5.0] - 2026-04-18

### Added
- `/discover` スキル（アイデア → 要件定義 → タスク分解の対話型スキル）
- `/discover` に仕様セルフレビューチェックポイント（Step 4 / Step 5 前の thinking.md §2 準拠チェック）
- `/close-chat` に CHANGELOG 整合性チェックステップ（Step 5.5）
- `/weekly-review` にドキュメント整合性チェック（ADR index・CHANGELOG drift・README stale 検出）
- `CLAUDE.md` Project Configuration に `SIDEKICK_VERSION` を追加
- ADR-0007（thinking-os positioning）、ADR-0008（MEMORY.md 廃止・auto-memory 一本化）
- 下流 PJ 向け移行ガイド `docs/migrations/memory-md-to-auto-memory.md`

### Changed
- README に `/discover` を反映、スキル総数 14 → 15、スキル間連携フロー図追加
- README / README.ja のスキル記述を「project-root MEMORY.md」→「auto-memory」に書き換え
- `/close-chat` / `/inventory` / `/setup` の MEMORY.md 参照を auto-memory 前提に統一
- `.claude/rules/documentation.md` / `knowledge-map.md` を auto-memory 一本化前提に書き換え
- CLAUDE.md H13 / ゲート3 を auto-memory 前提に明文化
- `.gitattributes` で全テキストファイルを LF 強制
- thinking.md を「入れ替え可能な思考OS」として位置づけ（ADR-0007）
- settings.json の hooks を公式 JSON フォーマットに移行

### Removed
- `.claude/templates/MEMORY.md`（ADR-0008 により廃止）
- `.gitignore` の `/MEMORY.md` エントリ（配置対象外になったため）

### Fixed
- hook の `echo` を `printf` に修正（Windows パスで全ガードが無効化されるバグ）
- SVG 内の "14 Skills" を "15 Skills" に修正

### Breaking Changes
- **下流 PJ**: project-root `/MEMORY.md` の手動移行が必要。`docs/migrations/memory-md-to-auto-memory.md` を参照

## [0.4.1] - 2026-04-09

### Changed
- settings.json の permissions.allow を `Bash(*)` に一本化（ADR-0002 ブラックリスト方式の完全準拠）
- guard-db-operation.sh: PRD DB 検出時に exit 0（警告）→ exit 2（ブロック）に強化
- permissions.deny に `prisma db push`（npx なし版）、`git push --force-with-lease` を追加
- README（EN/JA）の防御モデル説明を4層構造（deny / guard / HARD / auto）に更新

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
