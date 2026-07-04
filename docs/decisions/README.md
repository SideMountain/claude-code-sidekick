# Architecture Decision Records

sidekick の設計判断とその根拠を記録する。

| ADR | タイトル | ステータス |
|-----|---------|-----------|
| 0001 | [バージョン管理と複数PJへの配信方式](0001-oss-distribution-strategy.md) | 改訂済み |
| 0002 | [自動実行のブラックリスト方式と2レーン制](0002-blacklist-execution-and-two-lanes.md) | 承認済み |
| 0003 | [無人実行のアーキテクチャ](0003-slack-cron-architecture.md) | 承認済み |
| 0004 | [Git を Source of Truth、外部DBはオプション](0004-context-consolidation-claude-code-first.md) | 承認済み |
| 0005 | [下流統合設計原則](0005-downstream-integration-principles.md) | 承認済み |
| 0006 | [開発と配布を単一リポに統合する](0006-single-repo-consolidation.md) | 採用（2026-06-13、二リポ運用版を supersede） |
| 0007 | [thinking.md を入れ替え可能な思考OSとして位置づけ](0007-thinking-os-positioning.md) | 承認済み |
| 0008 | [project-root MEMORY.md を廃止し auto-memory に一本化](0008-memory-md-to-auto-memory.md) | 承認済み |
| 0009 | [リリース取り込み設計（温度感・思想漏洩防止・スキップ制御）](0009-release-adoption-design.md) | 承認済み |
| 0010 | [思考OS の2層構造（L0/L1）と配布・還流メカニズム](0010-thinking-os-layers-and-reflow.md) | 承認済み（一部 Superseded by 0013, 0016） |
| 0011 | （予約: v1.0 破壊変更内容を後日定義） | — |
| 0012 | [Notion 判断ログ同期](0012-notion-judgment-sync.md) | 承認済み |
| 0013 | [思考OS の 3 層 brain 構造](0013-brain-three-layer-structure.md) | 一部 Superseded by 0016 |
| 0014 | [sidekick の ADR は下流 PJ に配布しない](0014-sidekick-adr-not-distributed.md) | 承認済み |
| 0015 | [下流 PJ の ccs 不意識運用原則](0015-downstream-ccs-unaware-operation.md) | 承認済み |
| 0016 | [brain の 2 層モデル化と上書き禁止運用](0016-brain-two-layer-model.md) | ドラフト |
| 0018 | [北極星と最小ループ（3 動詞）](0018-north-star-and-minimal-loop.md) | 採用（2026-06-13） |
| 0019 | [UI/UX ハーネスの段階導入（3 層）](0019-uiux-harness-three-layer.md) | 採用（2026-06-13、v0.8.x で P1 着手） |
| 0020 | [Spine-Driven の棚卸しと構想の凍結（ledger 型）](0020-spine-driven-ledger.md) | 採用（2026-06-17、ledger 型・新機能なし） |
| 0021 | [stack pack 方式の確立と Next.js 参照インスタンス](0021-stack-pack-and-nextjs-instance.md) | 採用（2026-06-17） |
| 0022 | [stack pack のサイクル統合・軽さドクトリン・intake routing](0022-stack-pack-cycle-integration.md) | 採用（2026-06-19、原則決定・配線は follow-up） |
| 0023 | [文脈経済（rate-cap 内で精度を落とさず長く稼働）](0023-context-economy.md) | 採用（2026-06-23、原則決定・実装は段階的） |
| 0024 | [自律ループと budget-gate（rate-cap 内の長時間・自律稼働）](0024-autonomous-loop-and-budget-gate.md) | 採用（2026-06-24、設計決定・強制配線は follow-up） |
| 0025 | [budget-gate の Stop hook 実配線](0025-budget-gate-stop-hook-wiring.md) | Proposed（2026-07-02、論点整理・実配線は実機検証後） |
| 0026 | [AUTO_MODE 既定値と「physically blocks」表現の整合](0026-auto-mode-default.md) | Proposed（2026-07-02、論点整理・既定変更は承認後） |
| 0027 | [公式スキル採用とラップ配布（OS 層 + 指揮者への縮約）](0027-official-skill-adoption-and-wrapping.md) | 採用（2026-07-04、方針決定・実装は WS1-WS7 で段階的） |