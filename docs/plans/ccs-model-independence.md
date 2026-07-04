# ccs モデル非依存化 + 文脈経済強化 — 実装計画

> 目的: **特定の上位モデルの可用性に依存せず、標準モデルでも ccs の品質下限（判断の再現性・安全・知識パイプライン）を構造で担保する**。同時に常駐トークン footprint を削減し、文脈経済（ADR-0023/0024/0025）の残タスクを完成させる。
> 診断日: 2026-07-04。全 18 スキル + hooks 9 本 + rules 15 本 + brain / CLAUDE.md を 4 系統並列で棚卸し。全量は [ccs-model-independence-diagnosis.md](ccs-model-independence-diagnosis.md)。
> 関連: ADR-0023（文脈経済 7 原則）/ ADR-0024・0025（budget-gate）/ ADR-0026（AUTO_MODE 既定・審議中）。コンテンツ制作系の別リポで先行する同型計画（3 形態外部化）の ccs 本体版。

---

## 0. 診断サマリ

**現状の品質は「hooks の強制層（決定的）」と「モデルの解釈力（暗黙）」の二本足で立っている。**

- 決定的（モデル非依存）な資産は hooks 9 本・/inventory・/token-audit 計測部・/adopt の severity 判定に集中。ここは強い
- 一方、スキル内の**判断ポイント約 60 箇所が prose 裁量**（「適切か」「妥当か」「同趣旨か」）でモデルの解釈力に依存。上位モデルは行間を埋めるが、標準モデルでは判定が甘くなる・全部 medium に潰れる・表層指摘に退化する
- 最重要発見 3 つ:
  1. **定量 rubric が既在なのに未配線** — review/references/scoring-guide.md の min(Code,Test,Ops) がどの SKILL.md からも参照されていない。配線だけで最終判定のブレが解消（費用対効果最大）
  2. **知識パイプライン = moat が最もモデル依存** — 「同趣旨」クラスタリング（3 件ルール）・原則への昇華・還流 3 分類が全部暗黙判断。しかも同一ロジックが 4 箇所に別文面で重複
  3. **無人実行の入口ゲートが自由裁量一文** — /auto-implement Phase 0 の「設計が確定しているか」が prose のみ

**方針: 骨格（隔離・Return Contract・昇格ラダー・強制層）は変えない。「判断の中身」を 4 形態に外部化する。**

| 形態 | 内容 | トークン費用 | モデル依存 |
|---|---|---|---|
| **A: few-shot** | 暗黙のトーン・形式・良し悪し判断を実例（OK/NG 対）の模倣に置換 | 呼出時のみ | 低（解釈→模倣） |
| **B: rubric** | 主観判定を YES/NO 質問群 + 閾値カウントに分解 | ほぼゼロ | 低 |
| **C: 決定的スクリプト** | grep / カウント / 日付比較で機械判定できるものをスクリプト化 | ゼロ | ゼロ |
| **D: harness 補強** | 真の難所（設計判断・矛盾裁定・root-cause）に敵対検証・premise-check・多視点 judge を構造として明示 | 増える | 本質的に残る |

（+ **E: 構造是正** = DRY 統合・行数超過分割・常駐ダイエット。モデル非依存化と同時にトークンを削る）

**文脈経済との統合原則**: 品質の下限は B/C が引く（トークン費用ゼロ・モデル非依存）。D はトークンを使う代わりに budget-gate の THROTTLE と連動して「幅」を調整できる — ADR-0024 決定 5「throttle が削るのは幅であって正しさではない」の実装的裏づけになる。A は「ルール解釈」を「実例模倣」に転換し、モデル tier 差の影響を最小化する。**B/C を先に敷くほど、D（fan-out）の発火条件を機械化でき、トークン削減とモデル非依存化は同じ施策になる。**

## 1. 残すもの（現状の強み — 触らない）

1. **hooks 強制層 9 本** — 保護ブランチ / .env / PRD DB / commit 規約 / PII / budget-gate。ブラックリスト方式（ADR-0002）ごと維持
2. **/inventory の決定的設計** — severity 判定・Critical フラグが bash 完結。他スキルの C 化の手本
3. **/token-audit Step 1-3** — 計測・cap 読取りが fail-open で決定的。確度表示・推測禁止も明文化済
4. **隔離 + Return Contract**（skill-agent-design.md）— per-call hygiene の骨格
5. **昇格ラダーの思想**（feedback → PJ brain → 個人 brain → OSS 還流）— 書き戻し先と判定だけ補強する
6. **/adopt の severity・差分抽出スクリプト資産**、6.4b @import 挿入の人手ゲート（機械化しないのが正しい）

## 2. 改善案（優先度順）

### P1【最優先・工数極小】レビュー判定の rubric 配線

- **問題**: scoring-guide.md の定量 rubric が未配線。総合判定の裁定が 5+1 箇所に分散し全て prose 裁量
- **改善**: /review Step 4 と各観点スキルの総合判定を「BLOCKER/WARN/INFO → スコア → min()」の機械集計に一本化（既存資産の配線が主）。review-design / review-spec の出力ラベル番号ズレ・総合判定行欠落も同時是正
- **効果**: 標準モデルの「甘い判定に流れる」を構造で止める。/auto-implement の無人レビュー安定にも直結
- **工数**: S

### P2【moat 防衛】知識パイプラインの rubric + few-shot 化

- **問題**: 「同趣旨」クラスタリング・昇華判定・還流 3 分類が暗黙判断 + 4 箇所重複。ccs の中核価値（知識パイプライン）が最もモデル依存
- **改善**:
  - 「同趣旨」ペア判定 rubric（同一トリガー / 同一是正行動 / 同一失敗モード → 2/3 YES）
  - 昇格・還流判定の few-shot 化 — **実績データが既にある**（昇格済/却下の実 feedback 16 件、還流フラグ処理履歴）。これを OK/NG 実例コーパスとして単一 reference に集約
  - 還流 3 分類ロジックを 4 箇所（close-chat / weekly-inventory / auto-implement / knowledge-map.md）から単一 reference 参照に統合（DRY）
  - 致命クラスを 4 カテゴリ閉集合 {データ喪失, 本番影響, セキュリティ, guard 無効化} に限定
- **工数**: M

### P3【無人実行の安全】/auto-implement 入口ゲートの rubric 化

- **問題**: Phase 0「設計が確定しているか」が prose 一文。無人モードの唯一の入口が最もモデル依存
- **改善**: ADR/Issue 存在の機械判定 + 「未決定の選択肢が残っているか」「曖昧語（だいたい・たぶん）を含むか」等の YES/NO rubric（1 つでも NG→停止）。DB マイグレーション要否も grep で決定化。Phase 3 のレビュー統合は /review verdict をそのまま採用（再判断させない）
- **工数**: S〜M

### P4【検知層の決定化】決定的スクリプト群（fitness / lint / doctor）

診断で C 分類となった約 25 箇所を、効果の高い順にスクリプト化する:

- **破壊的マイグレーション検出の共通化** — 4 重定義（review-code / review-ops / review-spec / deploy-strategy.md）→ scripts/ に 1 本
- **/review fast-gate の観点判定スクリプト**（変更パス → 観点集合）
- **release lint** — 3 点一致（title prefix / banner / severity マーカー）+ [Unreleased] 空チェック + semver bump 判定を gh release create 前に機械検証
- **setup doctor** — Step 1E の 9 項目存在確認を ✅/❌ 表で機械出力
- **ADR 採番ワンライナー**（並行 worktree の採番衝突防止）+ README 索引突合
- **a11y / design-token grep**（alt 欠落・label 無し input・hex 直書き・コントラスト計算）
- **エラー握りつぶし検出**（catch 内に logger/captureException なし）
- **弱いアサーション grep**・テスト対応マッピング・sidekick バージョンチェックの共有スクリプト化（2 重実装解消）
- **trivial-gating の機械判定**（変更ファイル数 + diff 行数 + パス種別 → fan-out 要否）— D 層の発火条件そのもの
- **guard ブロックログ + 集計**（weekly-inventory Step 5c を実行可能にする）
- **工数**: M〜L（独立スクリプトの積み上げなので分割 PR 可）

### P5【真の難所】harness 補強 — 「上位モデルの深さ」を構造で再現する

診断で D 分類となった箇所（観点間矛盾裁定・ギャップ分析・DB 設計・レースコンディション・モック突合・仕様突合・判断の構造化・バックテスト）に、暗黙で行われていた思考を明示ステップとして書き込む:

1. **難所の閉集合列挙**（context-economy.md §8 の改訂）— {設計判断, root-cause, 矛盾裁定, セキュリティ, 最終 judge} + 「判定不能時は上位既定」。「難所かどうか」の判定自体を裁量にしない
2. **敵対検証ステップの標準化** — 「推奨案を落とす理由を 1 つ挙げよ」（/discover）、「この統合で消えるアサートが捕まえていたバグを挙げよ」（/tune）、観点ペアの両立判定（/review Step 3a）。refute-first を skill 本文に固定
3. **premise-check の明示化** — ギャップ分析の前に「ゴールの前提を疑う」、水平展開の前に「抽出パターンを 1 行宣言」
4. **2 段手順の足場** — 仕様突合は「受入条件を先に抽出→各条件に実装行を対応付け」、モック突合は「型ファイルを必ず Read→対比表」
5. **budget-gate 連動** — D 層の fan-out 幅（敵対検証の票数・judge 視点数）だけを THROTTLE で縮退し、B/C 層は常時フル稼働。縮退時は ledger に「未実施の検証」を明示（silent drop 禁止・ADR-0023 決定 1-6）
- **工数**: M

### P6【トークン削減本体】常駐ダイエット + DRY 統合

- **CLAUDE.md 232 行**: HARD 一覧とブラックリスト表の二重掲載を対応表参照に統合
- **rules 統合**: context-economy + context-management（compact 閾値の数値不一致解消込み）、documentation + knowledge-map の表重複解消
- **path-scope 化**: code-quality（src 系）、deploy-strategy（prisma/scripts）、database（設定ゲート検討）
- **dead weight 退避**: task-management.md の Notion Layer 2 節（約 60 行）を .example 側へ
- **SKILL.md 分割**: setup 518 / adopt 461 / auto-implement 393（レポート実例 115 行）/ weekly-inventory 351 / close-chat 304（Notion 節 80 行）/ review 203 → references/ へ
- **pii-prevention の bash 40 行**を githooks/pre-commit と共通化（実装重複解消）
- **効果目安**: 常駐 約 1,092 行 → 700 行台（-30% 強）。/token-audit で before/after 実測
- **工数**: M（独立 PR 可・いつでも着手可能）

### P7【強制層の穴埋め】HARD-hook 対応漏れ

- H10/H11（STG 時 PR 経路）: `gh pr create` の base/head 検査を guard-bash に追加（STG_ENABLED 時のみ）
- H13（worktree→MEMORY 記録順序）: PostToolUse reminder で認知層を機械化
- H14（マイグレーション並行禁止）: Active Work 照合は将来課題として ledger へ
- **H7/H8 × AUTO_MODE 既定 true の裁定**: guard-bash.sh:65 の `SIDEKICK_AUTO:-true` は「必ずユーザー確認」の HARD と緊張関係。**ADR-0026 の審議項目に正式に載せる**（本計画からの入力）
- **工数**: S〜M

### 並走スレッド: 文脈経済 PR3（既存 backlog の完成）

- prompt-reminder.sh への「閾値超過時のみ cognition 行」注入（ADR-0024 決定 4）
- /setup の capturer 稼働検証 gating（ADR-0025 follow-up）
- **tiering A/B の再定義**: 「上位モデル単発 vs 標準モデル + harness（P5 適用後）」の worth-it 実測に転換。/token-audit Step 3 のプロトコルを使用し、tokens 差 + 見落とし findings 差を計測。P1-P5 適用前後の判定一致率も同プロトコルで測る
- **工数**: S（PR3）+ 実測は運用内

## 3. 実装順

| Phase | 内容 | 根拠 |
|---|---|---|
| **Phase 0（完了）** | 本診断 + 本計画。**rubric 原案・exemplar（few-shot 実例）の起草は上位モデルが利用可能なうちに行うのが最も効く**（判断の蒸留は蒸留元の質に依存する） | 診断済み |
| **Phase 1** | P1 rubric 配線 + P3 入口ゲート + P2 知識パイプライン | 効果最大・moat 防衛・無人安全 |
| **Phase 2** | P4 スクリプト群 + PR3 | 検知層の決定化。分割 PR で積み上げ |
| **Phase 3** | P5 harness 補強 + P7 hook 穴埋め | B/C の土台の上に D を載せる順序 |
| **Phase 4** | P6 常駐ダイエット | 独立・いつでも。Phase 1-3 と衝突しない範囲で先行可 |

## 4. 検証方法

1. **判定一致率 A/B**: 同一 diff を rubric 配線前/後の標準モデルにレビューさせ、上位モデルの判定との一致率を比較（P1-P3 の効果測定）
2. **worth-it 実測**: 上位モデル単発 vs 標準モデル+harness で tokens 差 + 見落とし findings 差（ADR-0023 決定 3 の実測プロトコル）
3. **footprint**: /token-audit で常駐行数・文字数の before/after（P6）
4. **lossy 検知**: THROTTLE 縮退時の「未実施検証」が ledger に残ることを確認（silent drop 禁止の担保）

## 5. 位置づけ

- コンテンツ制作系の別リポで先行した「判断の外部化」計画の ccs 本体版。うまくいったパターン（corpus / rubric / lint）の横展開 + ccs 固有の第 4 形態（D: harness 補強）を追加した
- 本計画は提案。各 Phase の着手前にオーナー承認を取り、変更は feature ブランチ + PR で行う
- ADR 候補: 「判断の 4 形態外部化 + 品質下限の構造担保」は ccs の設計原則として ADR 化する価値がある（Phase 1 着手時に /record-decision）
