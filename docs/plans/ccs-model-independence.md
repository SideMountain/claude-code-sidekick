# ccs モデル非依存化 + スキル刷新（公式採用方針）— 実装計画

> 目的: **人間の brain（判断軸・思想）に沿って、AI が自律的かつ安全に動くハーネス**という ccs の本質に立ち返り、(1) commodity 化した能力は公式スキルに委ね、ccs を「OS 層 + 指揮者」に縮約する (2) 標準モデルでも品質下限を構造で担保する (3) 常駐トークン footprint を削減する。
> 診断日: 2026-07-04。全量診断は [ccs-model-independence-diagnosis.md](ccs-model-independence-diagnosis.md)（本計画の素材。file:line 付き 60 箇所）。
> 関連: ADR-0023/0024/0025（文脈経済・budget-gate）/ ADR-0026（AUTO_MODE 既定・審議中）/ ADR-0027（公式スキル採用方針・本計画から起草）。

---

## 0. 決定した方向性

1. **公式採用方針** — 公式スキルが成熟した領域（レビュー・検証・反復実行・スケジュール・計画）は自前実装をやめ、**ccs は公式スキルをラップ（PJ 規範を注入）して配布**する。公式の鮮度は /weekly-inventory・news-upstream で定常監視し、skills/rules を刷新し続ける
2. **review 系 6 スキルは薄いアダプタに縮退** — 機構は公式 /code-review に委ね、PJ 固有部分（HARD 照合・ADR 整合・design-system 準拠・PII・総合判定 rubric）だけを注入層に残す
3. **ccs が自前で持ち続けるもの** — brain / rules / hooks（強制層）/ 知識パイプライン（close-chat・weekly-inventory・inventory）/ 文脈経済(token-audit・budget-gate)/ 配布系（setup・release・adopt）/ 指揮者（auto-implement 刷新版）

**実測の裏づけ**: 同一素材を上位モデルと標準モデルで二重起草しブラインド審査（6 判定）した結果、**差は事実忠実性に集中**した（2026-07-04・別リポ実測）。標準モデル補強の主軸を「一次ソース確認の rubric 化・検証ステップの構造化」に置く本計画の方向と整合する。

## 1. 公式スキルの裏取り結果（2026-07-04・公式ドキュメント確認）

| 公式機能 | 要点 | ccs への含意 |
|---|---|---|
| /code-review | effort 5 段階 + ultra（クラウド多エージェント）。**REVIEW.md で PJ 観点を最優先注入できる**（公式サポート） | review アダプタは「コード」でなくほぼ「設定」で実現可能 |
| /verify, /run | v2.1.145+。**per-project で教える前提**のスキル | /setup がブートストラップを面倒見る（下流負荷を ccs が肩代わり） |
| /simplify | v2.1.154+ で cleanup 専用に挙動変更 | バージョン下限に注意 |
| /goal | **完了条件を設定し複数ターン自動実行するコマンド**（Stop hook ベース・軽量モデル評価器） | /discover の代替ではない。**auto-implement 刷新の完了条件部品** |
| /loop, /schedule | 反復実行 / クラウド routines | 自律ループ・定常 watch の部品 |
| /batch | 並列大規模変更（5-30 worktree を自動分割） | 指揮者の並列実行部品。H12 worktree 運用と整合 |
| plan mode / Tasks | 計画立案・タスク管理 | /discover の構造化フローと重複する部分の委譲先 |
| スキル上書き | 優先度: enterprise > personal > **project** > bundled。PJ の .claude/skills/ 同名定義で公式を置換できる | ラップ配布の実装手段そのもの |
| 存在チェック | /skills パース or バージョン比較で機械判定可能 | WS1 境界層（feature gate）の実装手段 |

制約（確認済み）: /code-review ultra はサブスク認証必須・従量課金あり。/verify・/run は教育が必要。公式スキルはバージョン差で欠けうる → **存在チェック + fallback の境界層が必須**（個人 brain「外部依存は失敗する前提」の適用）。

## 2. スキル仕分け（確定版）

| ccs スキル | 処遇 | 備考 |
|---|---|---|
| review + review-code/test/ops/design/spec | **6→1 アダプタ化** | PJ 観点は REVIEW.md + rubric に蒸留。診断 60 箇所が抽出素材 |
| discover | **薄型化** | 構造化フローは plan mode へ委譲。brain 照合（NG フィルター・判断原則評価・knowledge-map ルーティング）だけ残す |
| auto-implement | **指揮者に刷新**（本丸） | 公式部品（/goal・/loop・/verify・/code-review・/batch・plan mode）を brain + HARD 制約下で組み合わせ、ledger（ADR-0024）と接続 |
| close-chat / weekly-inventory / inventory | **残す + 強化** | 知識パイプライン = moat。weekly-inventory に公式鮮度 watch を追加（WS7） |
| token-audit | **残す** | 文脈経済の検知層 |
| setup | **残す + 拡張** | 公式ラップの配線・REVIEW.md 生成・/verify /run のブートストラップを追加 |
| release / adopt-sidekick-update / record-decision | **残す（配布系・小）** | ccs 自身の配布ループ |
| news / tune | **残す（縮小検討）** | news は要約系で軽量化余地。tune のテスト棚卸し・CI 高速化は独自価値 |

## 3. ワークストリーム

### WS1: 公式採用の境界層（最初にやる・全 WS の前提）

- ADR-0027 起草: 「公式スキル採用 + ラップ配布 + 鮮度 watch」のアーキテクチャ決定
- **feature gate**: 公式スキル存在チェック（/skills パース or バージョン下限判定）を hook-helpers に実装。不在時は fallback（従来 ccs 実装 or 明示 WARN）で silent 破綻させない
- ラップ規約を skill-agent-design.md に追記: 「公式に委ねる部分 / ccs が注入する部分（brain・HARD・rubric）」の境界の書き方
- 工数: S〜M

### WS2: review 刷新（6→1 アダプタ + REVIEW.md）

- REVIEW.md に PJ 観点を蒸留: HARD 照合・ADR/仕様書整合・design-system 準拠・PII・破壊的マイグレーション。診断の review 系 60 箇所（うち rubric 化可能 B 分類）を素材にする
- scoring-guide.md の min() 総合判定を最終ゲートとして配線（診断の最重要発見 #1。アダプタの唯一のロジック）
- 決定的検査（破壊的キーワード grep・a11y grep・エラー握りつぶし grep 等の旧 P4 該当分）は fitness スクリプトとして前置し、公式レビューの前に機械で落とす
- /setup に REVIEW.md 生成ステップを追加（下流 PJ が同じ恩恵を受ける = 北極星「意識せず恩恵」）
- 旧 6 スキルは deprecation（1 リリース残して撤去。下流移行ガイド付き）
- 工数: M

### WS3: auto-implement 指揮者化

- 入口ゲートの rubric 化（診断 P3）: 設計確定判定を YES/NO 化（1 つでも NG→停止）。無人実行の安全の要
- 実行ループを公式部品で再構成: plan mode（分解）→ /goal（完了条件宣言）→ 実装 → /verify（動作実証）→ /code-review + アダプタ（判定）→ ledger 記録。並列時は /batch を検討
- budget-gate 連動: THROTTLE 時は fan-out 幅のみ縮退、縮退内容を ledger に明示（silent drop 禁止）
- 難所の閉集合 {設計判断, root-cause, 矛盾裁定, セキュリティ, 最終 judge} + 判定不能時は上位既定（context-economy §8 改訂）
- 工数: M〜L

### WS4: 標準モデルの安全稼働・最小セット（方向性に依存しない恒久項目）

- **ADR-0026 の裁定**: guard-bash の `AUTO_MODE` 既定 true と H7/H8「必ずユーザー確認」の緊張関係を決着（無人稼働の前提として最優先審議）
- hooks 穴埋め: H10/H11（STG 時 PR 経路の guard 化）・H13（worktree→MEMORY 順序の PostToolUse reminder）
- 文脈経済 PR3: prompt-reminder への閾値超過時のみ cognition 行 + /setup の capturer 検証 gating
- 事実忠実性の補強（A/B 実測が根拠）: 「一次ソースを当該セッションで見たか YES/NO → NO なら確度ラベル必須」を確度表示ゲート（CLAUDE.md ゲート 2）の発火条件として明文化
- 工数: S〜M

### WS5: 残すコアへの rubric + few-shot 適用（旧 P2 縮小版）

- 知識パイプライン: 「同趣旨」ペア判定 rubric / 昇格・還流判定の few-shot 化（昇格済・却下の実 feedback 16 件を実例コーパスに）/ 還流 3 分類の 4 箇所重複を単一 reference に統合 / 致命クラス 4 カテゴリ閉集合
- close-chat・weekly-inventory・inventory・token-audit の診断指摘（B/C 分類）を適用
- 工数: M

### WS6: 常駐ダイエット（独立・いつでも着手可）

- CLAUDE.md 232 行の二重掲載解消 / context-economy と context-management 統合（compact 閾値の数値不一致解消）/ task-management の Notion 節退避 / path-scope 化 / SKILL.md 分割
- **WS2 のスキル撤去と相乗**: review 系 6 スキルの縮約自体が最大のダイエット
- 効果目安: 常駐 約 1,092 行 → 700 行台 + スキル本文の大幅減。/token-audit で before/after 実測
- 工数: M

### WS7: 鮮度 watch の定常化（公式採用方針の持続機構）

- weekly-inventory に「公式スキル差分チェック」ステップを追加: バージョン・新規スキル・挙動変更を検知し、ccs ラッパーとの gap を Issue 化
- news-upstream の gap 分析を「ラッパー刷新の入力」として正式に位置づけ（現状の watch 項目を機械チェック化）
- 工数: S

## 4. 実装順と期限

| Phase | 内容 | 実行者 |
|---|---|---|
| **Phase 0（上位モデル可用期間内・最優先）** | 本計画確定 + ADR-0027/0026 起草 + **rubric 原案・exemplar（few-shot 実例）・REVIEW.md 原案の起草**。判断基準の蒸留は蒸留元の質に依存するため、ここだけは上位モデルで行う | 上位モデル |
| Phase 1 | WS1 境界層 + WS4 安全最小セット | 標準モデル + サブエージェント |
| Phase 2 | WS2 review 刷新 + WS3 指揮者化 | 同上（worktree 分割・WS 単位で PR） |
| Phase 3 | WS5 コア強化 + WS7 鮮度 watch | 同上 |
| Phase 4 | WS6 ダイエット（随時・独立 PR） | 同上 |

サブエージェント委任の分割単位: WS ごとに worktree + feature ブランチを分け、各 WS 内は「起草（rubric/設定）→ 実装 → /review → PR」の定型で回す。WS2 と WS6 はファイル競合があるため順次（WS2 先行）。

## 5. 検証方法

1. **判定一致率 A/B**: 同一 diff を「アダプタ + REVIEW.md 適用前/後」の標準モデルにレビューさせ、上位モデル判定との一致率を比較
2. **worth-it 実測**: 上位モデル単発 vs 標準モデル + harness の tokens 差 + 見落とし findings 差（ADR-0023 決定 3・/token-audit Step 3 プロトコル）
3. **footprint**: /token-audit で常駐行数・文字数の before/after（WS6）
4. **lossy 検知**: THROTTLE 縮退時の「未実施検証」が ledger に残ることを確認

## 6. 位置づけ

- コンテンツ制作系の別リポで先行した「判断の外部化」計画（corpus / rubric / lint）の ccs 本体版。ccs 固有の追加は「公式採用 + ラップ配布」（WS1/WS7）と「harness 補強」（WS3）
- 本計画は提案。各 WS の着手前にオーナー承認を取り、変更は feature ブランチ + PR で行う
- 全量診断（付録）は WS2/WS5 の実装時に file:line の一次ソースとして参照する
