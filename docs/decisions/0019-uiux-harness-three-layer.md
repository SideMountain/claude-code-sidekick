# ADR-0019: UI/UX ハーネスの段階導入（3 層）

## ステータス

採用（2026-06-13）— v0.8.x で P1 着手。

## 背景

ハーネスは安全・思考 OS・スキルを扱うが、UI/UX 品質（デザインシステム準拠・デザイントークン・アクセシビリティ・ビジュアルリグレッション）の受け皿が薄い。

一方、UI を持たない PJ に UI 系のコストを課してはならない。北極星（ADR-0018）に照らし、UI なし PJ は無コスト、UI あり PJ も opt-in でデフォルト安全に倒れる設計が要る。

### path-scoped rule の制約

design-system のガイドラインを「UI ファイルを編集するときだけ」context に載せる方式として、`paths:` frontmatter による path-scoped rule を検討した。検証の結果、Claude Code の `paths:` frontmatter には次の制約がある。

- **新規ファイル作成（Write）では発火しない**。Read および既存ファイルの Edit でのみ発火する（公式 issue #23478 は "not planned" でクローズ、修正予定なし）
- 文書化された `paths:` 記法に silent failure の報告がある（issue #17204）

このため、path-scoped rule 単独では「新規 UI ファイルを作成する瞬間にガイドを効かせる」用途が成立しない。新規作成を含めてカバーするには、PostToolUse hook による検知が要る。

## 決定

UI/UX ハーネスを **3 層で段階導入する**。各層は opt-in（UI ありと申告した PJ にのみ配置）。

### v0.8.x（P1）

- **design-system.md**: デザインシステム準拠ガイド。path-scoped（`paths:`）は既存ファイル編集時の補助として使い、主機構にはしない
- **PostToolUse UI 検知 hook**: UI ファイルの作成・編集を検知する主機構（`paths:` が Write で発火しない制約を補う、軽量検知のみ）
- **`/setup` の UI opt-in ヒアリング**: UI ありと申告した PJ にのみ design-system.md と hook を配置する。UI なし PJ はコストゼロ
- **review-design への接続 + `/verify` 委譲ポインタ**
- lint の実行は PR 前ゲートに一本化する（PostToolUse での毎回 lint 実行は WSL 環境で遅延・hang リスクがあるため避ける）

### v0.9（P2）

- デザイントークン lint（warn → error の段階導入）
- アクセシビリティ smoke（axe、CI で実行）

### v1.0（P3）

- ビジュアルリグレッションテスト（opt-in）
- ブラウザ操作スキル / Stop hook ゲートの再評価

### やらないこと

| 項目 | 理由 |
|---|---|
| ブラウザ自動操作 MCP の常設 | タスクあたりのトークンコストが過大 |
| ブラウザ常駐連携 | 実行環境の制約（WSL 非サポート） |
| デザインツール MCP のデフォルト化 | 無料枠で実用に満たない |
| Lighthouse CI | コストに対して得られる検知が薄い |

## 理由

1. **北極星（ADR-0018）**: UI なし PJ は無コスト、UI あり PJ は opt-in でデフォルト安全。利用者が組み合わせを意識しない
2. **仕組み化の 3 層**: PostToolUse 検知 hook が強制・検知層を担う。能動的に覚える接点を増やさない
3. **外部依存は失敗前提**: 重い常駐 MCP を避け、軽量検知 + PR 前ゲートに寄せる
4. **環境制約を設計に織り込む**: `paths:` の Write 非発火という Claude Code の制約を前提に、新規作成は hook でカバーする

## 却下した案

- **path-scoped rule 単独**: Write（新規作成）で発火せず、新規 UI ファイルの作成時にガイドが効かない
- **ブラウザ自動操作 MCP の常設**: トークンコストが過大
- **lint を PostToolUse で毎回実行**: WSL 環境で遅延・hang リスク。PR 前ゲートに一本化する

## 影響

- v0.8.x: design-system.md テンプレート + PostToolUse 検知 hook + `/setup` UI ヒアリング + review-design 接続を追加する
- 配布前に UI を持つ PJ で 1 サイクル dogfood してから配布する（配布リポ自体は UI を持たないため）

## 関連 ADR

- ADR-0006: 開発と配布の単一リポ統合
- ADR-0018: 北極星と最小ループ（受動層中心・opt-in の原則）
- ADR-0002: 自動実行のブラックリスト方式（hook 強制層）
