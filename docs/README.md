# docs/ 索引

> 読者: OSS 利用者・ccs 保守者（人間） · 役割: 導線（このディレクトリの読み順と使い分け） · ロード: 非ロード（人間のみが読む）

sidekick のドキュメントは「誰が・何のために読むか」でレイヤーが分かれています。目的に合う入口から読んでください。

## 読者別の入口

| 知りたいこと | 読むもの | 読者 |
|---|---|---|
| sidekick とは何か・導入方法 | [English README](../README.md) / [日本語 README](../README.ja.md) | OSS 利用者 |
| 設計思想の全体像（1枚・**思想の背骨の単一ソース**） | [design-philosophy.md](./design-philosophy.md) / [ja](./design-philosophy.ja.md) | OSS 利用者・保守者 |
| 全機能とライフサイクル輪の地図 | [lifecycle.md](./lifecycle.md) / [ja](./lifecycle.ja.md) | 保守者 |
| 個別の設計判断の「なぜ」 | [ADR 索引](./decisions/README.md) | OSS 利用者・保守者 |
| 夜間 cron・無人実行の設定手順 | [cron-setup-guide.md](./cron-setup-guide.md) | OSS 利用者（運用者） |
| E2E（Playwright）の導入手順 | [playwright-setup-guide.md](./playwright-setup-guide.md) | OSS 利用者 |
| バージョン更新時の手動移行手順 | [migrations/](./migrations/README.md) | OSS 利用者 |

## このディレクトリに置かないもの

- 下流プロジェクトの Claude が runtime で読む規範・手順 → `.claude/rules/`（常駐・path-scoped）と `.claude/docs/`（遅延ロード）にあります
- 作業中の計画・診断 → 置きません（ADR-0030。backlog / GitHub Issue が正位置です）

執筆規約（文体・読者宣言・単一ソース原則）は `.claude/rules/oss-doc-authoring.md` と ADR-0033 を参照してください。
