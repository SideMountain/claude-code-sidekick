# Architecture Decision Records

sidekick の設計判断とその根拠を記録する。

| ADR | タイトル | ステータス |
|-----|---------|-----------|
| 0001 | [バージョン管理と複数PJへの配信方式](0001-oss-distribution-strategy.md) | 改訂済み |
| 0002 | [自動実行のブラックリスト方式と2レーン制](0002-blacklist-execution-and-two-lanes.md) | 承認済み |
| 0003 | [無人実行のアーキテクチャ](0003-slack-cron-architecture.md) | 承認済み |
| 0004 | [Git を Source of Truth、外部DBはオプション](0004-context-consolidation-claude-code-first.md) | 承認済み |
| 0005 | [下流統合設計原則](0005-downstream-integration-principles.md) | 承認済み |
| 0006 | [sidekick と claude-code-sidekick の2リポ管理](0006-two-repo-management.md) | 承認済み |
| 0007 | [thinking.md を入れ替え可能な思考OSとして位置づけ](0007-thinking-os-positioning.md) | 承認済み |
| 0008 | [project-root MEMORY.md を廃止し auto-memory に一本化](0008-memory-md-to-auto-memory.md) | 承認済み |
| 0009 | [リリース取り込み設計（温度感・思想漏洩防止・スキップ制御）](0009-release-adoption-design.md) | 承認済み |
| 0010 | [思考OS の2層構造（L0/L1）と配布・還流メカニズム](0010-thinking-os-layers-and-reflow.md) | 承認済み（一部 Superseded by 0013） |
| 0011 | （予約: v1.0 破壊変更内容を後日定義） | — |
| 0012 | [Notion 判断ログ同期](0012-notion-judgment-sync.md) | 承認済み |
| 0013 | [思考OS の 3 層 brain 構造](0013-brain-three-layer-structure.md) | ドラフト |
| 0014 | [sidekick の ADR は下流 PJ に配布しない](0014-sidekick-adr-not-distributed.md) | 承認済み |
| 0015 | [下流 PJ の ccs 不意識運用原則](0015-downstream-ccs-unaware-operation.md) | 承認済み |