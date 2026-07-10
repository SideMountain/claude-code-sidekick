# ADR-0031: 現在状態オラクル原則（時点根拠 ≠ 現在の真）

## ステータス

採用（2026-07-10）。実装済み（`context-economy.md` §1/§5 追記 + `.claude/docs/current-state-oracle.md` 新設）。前提は ADR-0023（文脈経済）・ADR-0028（難所ladder）。

## 背景

親エージェントが subagent の調査報告を土台に不可逆操作（DDL・スキーマ変更・削除）を行う構成には、既存ルールで塞げていない欠陥混入経路がある: **子が本物の一次ソースを引用していても、それが現在の状態である保証はない**。追記型履歴（DB migration・CHANGELOG・ADR 系列）では過去のどの 1 点の定義を引いても、後続の DROP / RENAME / Superseded で無効化されていることがあり、時点根拠を確証として採用すると「撤去済みオブジェクトへの DDL」のような、適用時まで発覚しない欠陥が混入する。

既存の防御層はこの経路に対して不完全である。(1) Return Contract（`context-economy.md` §1）は出力の圧縮契約であって鮮度・確証の契約ではない。(2) 「機械で分かることは LLM に判定させない」（§5）は原則として存在するが、「現存・有効性」がその機械判定クラスに含まれることと、確認先が履歴でなく導出済み現在状態であるべきことが未定義。(3) ハーネスの鮮度強制（Edit ツールの Read-before-Edit）は編集対象ファイル自体にしか働かず、DB スキーマとファイル横断結合には相当物がない。

## 決定

1. **現在状態オラクル原則を §5 に追加**: テーブル / カラム / ポリシー / シンボルの「存在するか・生きているか」は機械判定クラスとし、LLM（自分・subagent とも）に判定させず、現在状態オラクル（working tree grep / typecheck / 生成 schema・型 / 履歴の機械 replay 結果）で確定する。追記型履歴では時点根拠 ≠ 現在の真。
2. **受信側 contract を §1 に追加**: 子が報告する load-bearing な事実（現存・仕様・「動く」）は伝聞として扱い、不可逆操作の土台にする前に親が一次確認する。Return Contract（出力側）と対になる受信側の規律。
3. **発火は操作クラスで固定する**: migration / DDL / スキーマ変更を書く前の参照先現存確認は、「この事実は load-bearing か」の判断を挟まず無条件必須とする。判断ベースの発火は判断ミスで沈黙するため、H1（DB 操作前の接続先確認を毎回）と同じ「判断しない」**発火形式**に揃え、`context-economy.md` ヘッダの HARD 例外として宣言する（H1 と異なり強制層 hook は未配線 — 強制は決定 5 の下流 CI が担う）。
4. **負荷は変更クラスで最小化する**: 重い検査（ephemeral replay）は真実が変わる場所（migration 変更）にだけ発火させ、コード側は生成型チェーン（migration → 生成型 → typecheck）への相乗りで追加コストゼロにする。変更クラス別トリガ表・実装パターンは `.claude/docs/current-state-oracle.md`（遅延ロード）に置き、常駐 rules には要約と参照のみ。
5. **ccs はテンプレ原則とパターンを配布し、CI 実装は各下流 PJ が持つ**: ephemeral replay CI・生成型 regen-diff 検査は DB / ORM 構成に依存するため、ccs core には入れない（core = stack 非依存の原則）。

## 選択肢と却下理由

- **A. 出力側 contract の強化のみ（報告に file:line 根拠を必須化）**: 子が本物だが古い一次ソースを引用する失敗モードをそのまま通す。根拠の実在と根拠の鮮度は別問題で、出力側だけでは塞げない。
- **B. 親が子の報告を全件再検証**: subagent の存在意義（文脈経済・探索の母数拡大）を毀損する。マルチエージェント構成のトークン倍率を払った上で全再検証するのは本末転倒。
- **C. load-bearing な事実だけ親が一次確認（判断ベース発火）**: 方向は正しいが、「load-bearing か」の判定自体が LLM の判断であり、判断ミスで発火しない。
- **D. 操作クラス固定発火 + 現在状態オラクル + 変更クラス別トリガ（採用）**: C との差は発火条件の決定性 — 「load-bearing か」でなく「migration / DDL を書くか」（機械判定可能）で発火する。加えて下流 PJ の強制層（CI ephemeral replay）まで接続でき、ルール文言に従わない実行系でも最終ゲートが効く。負荷はトリガ表で migration 変更時に局所化する。

## 検証

- 公式一次ソース確認: subagent は既定で親モデルを継承し（Agent SDK docs `model` フィールド「Defaults to main model if omitted」）、公式ガイダンスの委任リスク軸は「判断タスクか否か」でなく objective / 出力形式 / 境界のスコープ欠如（Anthropic multi-agent research system）。本 ADR の「タスクを機械判定クラスと判断クラスに二分し、判断クラスはスコープして委任する」はこれと整合し、「subagent を機械作業専用に格下げする」案を採らない根拠とした。
- 追記後の `context-economy.md` は 85 行、新設 doc は 73 行（`wc -l` 実測。200 行以内・GUIDE 準拠）。
- 新設 doc は遅延ロード（rules から参照のみ・常駐増ゼロ）。
- L1 R3 敵対検証（独立レビュー・6 観点: 内部矛盾 / グレード整合 / 参照整合 / OSS 作法 / 事実主張 / 消失テスト）を通過。グレード宣言（HARD 例外のヘッダ明記）と「動く」= 実行（§8 L3）の明示はこの検証観点を満たす形で確定。
- PII スキャン: 検出ゼロ（scan_pii 通過）。

## 影響

- `.claude/rules/context-economy.md`（§1 受信側 contract・§5 機械判定クラス追記）、新規 `.claude/docs/current-state-oracle.md`。
- 下流 PJ への follow-up（本 ADR の範囲外）: migration を持つ PJ での ephemeral replay CI・生成型 regen-diff 検査・migration Write 時 advisory hook の実装。パターンは新設 doc に記載済み。
- 既存の難所 ladder（§8）との関係: 本原則は ladder の前段（委任・受信の作法）であり、難所判定・検証量エスカレーションは従来通り §8 が担う。
