# Architecture Decision Records

sidekick の設計判断とその根拠を記録する。

| ADR | タイトル | ステータス |
|-----|---------|-----------|
| 0001 | [バージョン管理と複数PJへの配信方式](0001-oss-distribution-strategy.md) | 改訂済み |
| 0002 | [自動実行のブラックリスト方式と2レーン制](0002-blacklist-execution-and-two-lanes.md) | 採用 |
| 0003 | [無人実行のアーキテクチャ](0003-slack-cron-architecture.md) | 採用 |
| 0004 | [Git を Source of Truth、外部DBはオプション](0004-context-consolidation-claude-code-first.md) | 採用 |
| 0005 | [下流統合設計原則](0005-downstream-integration-principles.md) | 採用 |
| 0006 | [開発と配布を単一リポに統合する](0006-single-repo-consolidation.md) | 採用（2026-06-13、二リポ運用版を supersede） |
| 0007 | [thinking.md を入れ替え可能な思考OSとして位置づけ](0007-thinking-os-positioning.md) | 採用 |
| 0008 | [project-root MEMORY.md を廃止し auto-memory に一本化](0008-memory-md-to-auto-memory.md) | 採用 |
| 0009 | [リリース取り込み設計（温度感・思想漏洩防止・スキップ制御）](0009-release-adoption-design.md) | 採用 |
| 0010 | [思考OS の2層構造（L0/L1）と配布・還流メカニズム](0010-thinking-os-layers-and-reflow.md) | 採用（一部 Superseded by 0013, 0016） |
| 0011 | （予約: v1.0 破壊変更内容を後日定義） | — |
| 0012 | [Notion 判断ログ同期](0012-notion-judgment-sync.md) | 採用 |
| 0013 | [思考OS の 3 層 brain 構造](0013-brain-three-layer-structure.md) | 一部 Superseded by 0016 |
| 0014 | [sidekick の ADR は下流 PJ に配布しない](0014-sidekick-adr-not-distributed.md) | 採用 |
| 0015 | [下流 PJ の ccs 不意識運用原則](0015-downstream-ccs-unaware-operation.md) | 採用 |
| 0016 | [brain の 2 層モデル化と上書き禁止運用](0016-brain-two-layer-model.md) | 採用（2026-07-06） |
| 0017 | （欠番: 保守者ローカル運用の判断のため本リポに未収録） | — |
| 0018 | [北極星と最小ループ（3 動詞）](0018-north-star-and-minimal-loop.md) | 採用（2026-06-13。用語「北極星」は ADR-0033 で「目的」に改称） |
| 0019 | [UI/UX ハーネスの段階導入（3 層）](0019-uiux-harness-three-layer.md) | 採用（2026-06-13、v0.8.x で P1 着手） |
| 0020 | [Spine-Driven の棚卸しと構想の凍結（ledger 型）](0020-spine-driven-ledger.md) | 採用（2026-06-17、ledger 型・新機能なし） |
| 0021 | [stack pack 方式の確立と Next.js 参照インスタンス](0021-stack-pack-and-nextjs-instance.md) | 採用（2026-06-17） |
| 0022 | [stack pack のサイクル統合・軽さドクトリン・intake routing](0022-stack-pack-cycle-integration.md) | 採用（2026-06-19、原則決定・配線は follow-up） |
| 0023 | [文脈経済（rate-cap 内で精度を落とさず長く稼働）](0023-context-economy.md) | 採用（2026-06-23、原則決定・実装は段階的） |
| 0024 | [自律ループと budget-gate（rate-cap 内の長時間・自律稼働）](0024-autonomous-loop-and-budget-gate.md) | 採用（2026-06-24、設計決定・強制配線は follow-up） |
| 0025 | [budget-gate の Stop hook 実配線](0025-budget-gate-stop-hook-wiring.md) | 採用（2026-07-02） |
| 0026 | [AUTO_MODE 既定値と「physically blocks」表現の整合](0026-auto-mode-default.md) | 採用（2026-07-04） |
| 0027 | [公式スキル採用とラップ配布（OS 層 + 指揮者への縮約）](0027-official-skill-adoption-and-wrapping.md) | 採用（2026-07-04、方針決定・実装は段階的） |
| 0028 | [モデル退役後の能力エスカレーション再定義（検証量 ladder + 凍結判定 corpus）](0028-capability-escalation-after-model-retirement.md) | 採用（2026-07-04） |
| 0029 | [推論プレイブックの二経路配布と意思決定3閾値](0029-reasoning-playbook-two-path-distribution.md) | 採用（2026-07-06） |
| 0030 | [内部計画文書の非配布ポリシー（docs/plans 廃止）](0030-internal-plans-not-distributed.md) | 採用（2026-07-06） |
| 0031 | [現在状態オラクル原則（時点根拠 ≠ 現在の真）](0031-current-state-oracle.md) | 採用（2026-07-10） |
| 0032 | [enforcement 層は fail-closed、advisory 層は fail-open + 検知](0032-enforcement-guards-fail-closed.md) | 採用（2026-07-10） |
| 0033 | [文書ガバナンス（文体標準・読者宣言・単一ソース原則）](0033-doc-governance-style-and-single-source.md) | 採用（2026-07-10） |