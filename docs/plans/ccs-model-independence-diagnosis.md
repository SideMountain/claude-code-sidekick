# ccs モデル非依存化 — 全量診断（生データ）

> [ccs-model-independence.md](ccs-model-independence.md)（実装計画）の付録。
> 全 18 スキル + hooks 9 本 + rules 15 本 + brain / CLAUDE.md を 4 系統並列で棚卸しした結果の全量。
> 診断日: 2026-07-04。実装時はこの file:line を一次ソースとして参照する（診断時点のスナップショットのため、実装前に該当行の現存を確認すること）。

## 分類の凡例

- **A: few-shot 化可能** — 実例（OK/NG 対）を repo に置けば標準モデルでも模倣で再現できる暗黙判断
- **B: rubric 化可能** — 主観判定を YES/NO 質問群 + 閾値カウントに分解できるもの
- **C: 決定的スクリプト化可能** — grep / カウント / 日付比較で機械判定できるのに prose のもの
- **D: 真の難所** — 設計判断・矛盾裁定・root-cause 分析など、モデル能力が本質の箇所（harness 補強候補）
- **E: 構造是正** — DRY 重複・200 行超過・常駐汚染などトークン浪費
- **影響度** — 標準モデルに落としたときの品質劣化の大きさ

---

## 系統1: review 系 6 スキル

### review（SKILL.md 203 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | review/SKILL.md:57-74 | 変更スコープ判定を prose 表で「照合し観点を決定する」 | C | 変更ファイル一覧→観点集合を返す glob 判定スクリプト（fast-gate と同型） | 高 |
| 2 | review/SKILL.md:112-116 | Step 3a 観点間矛盾チェック（矛盾の定義なし） | D | 敵対検証 fan-out: 観点ペアごとに「両立するか YES/NO+根拠行」を問う judge ステップ明示 | 高 |
| 3 | review/SKILL.md:155 | 最終判定 3 値が完全にモデル裁量 | B | references/scoring-guide.md の min(Code,Test,Ops) rubric を SKILL.md から明示参照・配線 | 高 |
| 4 | review/references/scoring-guide.md:25-35 | 定量 rubric が存在するのに SKILL.md から読み込み指示なし | E | Step 4 に「scoring-guide.md を Read して算出」を 1 行追加（既存資産の未配線解消） | 高 |
| 5 | review/SKILL.md:167 | 「挙動に不安があれば /verify」（不安=裁量） | B | 「diff がランタイム表面（app/api/UI）に触れる→/verify 提案」の YES/NO 条件化 | 中 |
| 6 | review/SKILL.md:193 | 「skills/review*/ 変更なら全観点実行を検討する」 | C | 検討でなく規則化: grep hit→全観点を Step 1.5 スクリプトに吸収 | 中 |
| 7 | review/SKILL.md:1-203 | 203 行で 200 行上限を超過 | E | 公式スキル使い分け表（178-189）を references/ へ分離 | 低 |

上位モデル前提 top2: ① Step 3a 観点間矛盾の裁定（操作的定義ゼロ・多視点統合が能力頼み） ② Step 4 最終判定（rubric 既在なのに未配線で、標準モデルは甘い判定に流れる）

### review-code（SKILL.md 189 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | review-code/SKILL.md:44-46 | コミット規約・保護ブランチ直コミットを checkbox で「確認する」 | C | conventional-commit 正規表現 + 背景/対応/影響の grep、git log ブランチ検査スクリプト | 低 |
| 2 | review-code/SKILL.md:63-64 | 「既存コードのパターンと一致しているか」（基準なし） | A | references/ に「準拠 OK 例 / NG 例」の実コード対を置き模倣で判定 | 高 |
| 3 | review-code/SKILL.md:81 | 「過度な抽象化をしていないか（YAGNI）」 | B | 「使用箇所 2 未満の汎用 I/F? 実装 1 個の interface? 未使用パラメータ?」YES 2 個以上で指摘 | 中 |
| 4 | review-code/SKILL.md:82 | 認知的複雑性「1 関数 15 行・ネスト 3 段」を prose で判定 | C | 行数・ネスト深さカウントスクリプト（数値既記載＝即機械化可） | 中 |
| 5 | review-code/SKILL.md:88-93 | DB 設計「正規化・NULL 戦略・Enum・onDelete が適切か」 | D | 真の難所。schema diff 限定で上位モデル / premise-check（「このリレーションの前提は?」）を明示 | 高 |
| 6 | review-code/SKILL.md:94-95 | マイグレーション破壊的キーワード検出が prose | C | DROP/ALTER TYPE/RENAME/NOT NULL の grep スクリプト化（横断 DRY #1 参照） | 中 |
| 7 | review-code/SKILL.md:97-109,144 | C5 水平展開: パターン抽出 + 過剰適用の裁量抑制 | D | 抽出パターンをユーザー可視の中間成果物（1 行宣言）にし、適用可否を premise-check | 高 |
| 8 | review-code/SKILL.md:116-119 | 「認証バイパスの可能性」「CSRF 対策」自由評価 | B+D | 機械質問群（route の auth wrapper 有無 grep = C）+ バイパス経路推論のみ D に残す | 高 |
| 9 | review-code/SKILL.md:175 | 総合判定 3 値がモデル裁量 | B | scoring-guide の BLOCKER/WARN/INFO→min() マッピングに接続 | 中 |

上位モデル前提 top2: ① C5 水平展開の「パターン抽出→適用範囲判断」 ② C4 DB 設計の「適切か」群（無基準の設計判断は標準モデルで表層指摘に退化しやすい）

### review-test（SKILL.md 163 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | review-test/SKILL.md:44-55 | テスト追加漏れを diff 一覧の目視対応付けで判定 | C | src 変更ファイル↔テストファイルの存在マッピングスクリプト（除外リスト込み） | 中 |
| 2 | review-test/SKILL.md:66-79 | 網羅性表はあるが充足判定が自由評価 | B | 対象関数ごとに「null 入力? 空配列? 未認証?」YES/NO 表 + 不足数閾値 | 中 |
| 3 | review-test/SKILL.md:85 | 弱いアサーションを prose 例示のみで検知 | C | toBeDefined/toBeTruthy/not.toThrow 単独の grep + OK/NG 例 few-shot | 中 |
| 4 | review-test/SKILL.md:86 | 「テスト名が明確か」 | A | 良名/悪名の実例ペアを置く | 低 |
| 5 | review-test/SKILL.md:88 | 「内部実装ではなく振る舞いをテストしているか」 | B+A | 「private/内部 state 直接参照? spy 対象が公開 I/F 外?」質問化 + NG 例 | 中 |
| 6 | review-test/SKILL.md:96 | 「モックの戻り値が実際の型・構造と一致しているか」 | D | 真の難所。型ファイルを必ず Read→対比表を出す突合手順を明示化 | 高 |
| 7 | review-test/SKILL.md:111 | 「実行時間が著しく増加していないか」（著しく=裁量） | C | 前回実行時間を .data/ に保存し +20% 閾値比較 | 低 |

上位モデル前提 top2: ① T4 モック正確性（実装・型・実データの三者突合は root-cause 級） ② T3 実装詳細非依存の判定（「振る舞い」の境界線が無例示）

### review-ops（SKILL.md 153 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | review-ops/SKILL.md:44-56 | O1 外部依存の特定と障害波及分析がフリーフォーム | D | 依存列挙は C（fetch/axios/prisma/SDK import の grep）に前出し、波及分析のみモデルに残す | 高 |
| 2 | review-ops/SKILL.md:58-66 | O2 レースコンディション検出 | D | find-then-update パターン候補を grep で列挙→各候補に premise-check | 高 |
| 3 | review-ops/SKILL.md:72 | 「try-catch で握りつぶしていないか」を prose 確認 | C | catch 内に captureException/logger 呼び出しなしを検出する grep | 高 |
| 4 | review-ops/SKILL.md:79-84 | O4 PII 検査を checkbox 目視 | C+E | pii-prevention.md の scan_pii 正規表現群を再利用（検知ロジックの二重保守解消） | 中 |
| 5 | review-ops/SKILL.md:90-93 | ロールバック可能性の自由評価 | B | 「migration 有? DROP 系有? backfill 有? feature-flag 有?」の決定木で機械分岐 | 中 |
| 6 | review-ops/SKILL.md:97-102 | コスト影響「クエリ数は妥当か」 | B+C | 閾値 rubric（1 リクエスト N クエリ以上で WARN）+ package.json diff 機械検出 | 低 |

上位モデル前提 top2: ① O2 レースコンディション検出（並行性推論は標準モデルで最も落ちやすい） ② O1 障害モード列挙（依存の特定漏れ=以降全滅、なのに列挙が非機械的）

### review-design（SKILL.md 88 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | review-design/SKILL.md:40 | 「既存画面と統一されているか」（アンカーなし） | A | 準拠 OK/NG コンポーネント実例（or 基準コンポーネント指名）を references/ に置く | 高 |
| 2 | review-design/SKILL.md:41 | 「フローに不自然な遷移がないか」（審美・UX 判断） | D | 難所として残し、多視点 judge（新規ユーザー視点/エラー時視点）prompt を明示 | 中 |
| 3 | review-design/SKILL.md:46 | design-system.md 準拠を prose で確認 | C | hex 直書き・任意 px 値・非トークン色の grep（fitness-function 型） | 中 |
| 4 | review-design/SKILL.md:52-55 | alt / label / コントラスト比を checkbox 目視 | C | alt 欠落・label 無し input の grep、コントラストは色ペア計算スクリプト | 高 |
| 5 | review-design/SKILL.md:60-64 | 出力ラベル [D1] が手順番号と 1 つズレ | E | 出力ラベルを D2-D4 に是正（統合時の対応付け事故防止） | 中 |
| 6 | review-design/SKILL.md:59-70 | 「総合判定」行がなく /review Step 4 との契約不一致 | E | 総合判定行（UI OK/指摘あり/対象外）を出力フォーマットに追加 | 中 |

上位モデル前提 top2: ① D2 一貫性・フロー判断（アンカー例ゼロの審美判断は標準モデルで generic 指摘化） ② D4 の大半（計算可能なコントラスト比等を「目視」に委ねている）

### review-spec（SKILL.md 87 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | review-spec/SKILL.md:39-40 | 「レスポンス型変更」「必須パラメータ追加」を prose 判定 | B+C | 型/スキーマ diff 限定質問群（削除フィールド有? optional→required 有?）に分解 | 高 |
| 2 | review-spec/SKILL.md:41 | 「エラーレスポンス形式が統一されているか」 | A | 正規のエラーレスポンス形式の実例 1 つを references/ に置き対比 | 中 |
| 3 | review-spec/SKILL.md:46 | 「設計書と実装が一致しているか」 | D | 受入条件を先に箇条書き抽出→各条件に実装該当行を対応付ける 2 段手順を明示 | 高 |
| 4 | review-spec/SKILL.md:47 | 「ADR 方針に沿っているか」（関連 ADR 特定も裁量） | D+C | 変更パス→関連 ADR の対応は grep で前出し、整合判定のみ残す | 中 |
| 5 | review-spec/SKILL.md:52 | Expand-Contract 準拠を prose チェック | C | 破壊的キーワード grep の共通スクリプト（横断 DRY #1） | 中 |
| 6 | review-spec/SKILL.md:59-63 | 出力ラベル [S1] が手順番号と 1 つズレ（design と同バグ） | E | 出力ラベルを S2-S4 に是正 | 中 |

上位モデル前提 top2: ① S3 仕様書と実装の意味的突合（prose 仕様→コードの対応付けは最難関・足場ゼロ） ② S2 破壊的変更の判定（型 diff の機械抽出なしにモデル読解だけで裁定）

### review 系横断の DRY 違反

1. **破壊的マイグレーション検出が 4 重定義** — review-code:94-95、review-ops:93、review-spec:52、rules/deploy-strategy.md。共通の決定的スクリプト 1 本に集約し、3 観点は結果を受け取るだけにする。
2. **越境チェックの鏡像重複** — 「障害シナリオのテスト有無」が review-test:118 と review-ops:109 で同一質問、「エラーハンドリング/ログ」が review-code:135 と review-ops:108 で同一。片側主管に一本化。
3. **総合判定の裁定ロジックが 5+1 箇所に分散・rubric 未配線** — 各観点スキルの 3 値判定と /review Step 4 が全て prose 裁量。scoring-guide.md:25-35 の min() rubric への機械集計一本化が最も費用対効果が高い（既存資産の配線だけで済む）。

---

## 系統2: ライフサイクル系 6 スキル

### discover（SKILL.md 191 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | discover/SKILL.md:38-44 | 「関連するコード・ファイルを探索」（関連性が暗黙） | C+D | ADR 一覧 / gh issue list / MEMORY grep は固定スクリプト化、関連度選別のみモデルに残す | 中 |
| 2 | discover/SKILL.md:89-105 | ギャップ分析が「整理する」の一語で方法論なし | D | premise-check 明示ステップ（ゴールの前提を先に疑う）+ 敵対検証（「このギャップ一覧に漏れは」を別視点 judge） | 高 |
| 3 | discover/SKILL.md:110 | 「過去の却下理由と矛盾しないか」checkbox | B+C | feedback を kw-grep で機械抽出→各件に「本提案と衝突するか YES/NO」rubric | 中 |
| 4 | discover/SKILL.md:117,130 | 選択肢評価と推奨裁定が全て暗黙 | D | 案ごとに原則別スコア表を強制 + 推奨前に「推奨案を落とす理由を 1 つ挙げよ」の敵対ステップ | 高 |
| 5 | discover/SKILL.md:133-137 | 比較表省略 3 条件の判定が主観 | B | 各条件を YES/NO 質問化、1 つも明確 YES でなければ省略禁止 | 中 |
| 6 | discover/SKILL.md:155-165 | タスク分解の基準が例 1 つのみ | A | 実セッション由来の OK/NG 分解例（粒度過大 / 完了条件曖昧の NG 例）を references/ に置く | 中 |
| 7 | discover/SKILL.md:188 | スコープ膨張検出が prose | B | 「Step 2 のスコープ合意文に含まれるか YES/NO」の明示質問 | 低 |

上位モデル前提 top2: ① Step 3 ギャップ分析（標準モデルは表層差分しか出せない） ② Step 4 の選択肢評価＋推奨裁定（判断原則との照合が完全に暗黙推論）

### auto-implement（SKILL.md 393 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | auto-implement/SKILL.md:35-36 | 無人実行ゲート「設計が確定しているか」が prose 一文 | B+C | ADR/Issue 本文の存在は grep で機械判定 +「未決定の選択肢が本文に残っているか」等 YES/NO rubric（1 つでも NO→停止） | 高 |
| 2 | auto-implement/SKILL.md:37 | 「DB マイグレーションが必要か」判定方法が無指定 | C | 作業範囲に schema/migrations パスへの言及・変更があるかを grep で決定的判定 | 高 |
| 3 | auto-implement/SKILL.md:78-84 | /review 結果の「修正後再レビュー」vs「ブロッカー」裁定 | D | /review 側 verdict をそのまま採用（再判断させない）+ 矛盾 findings は多視点 judge へ fan-out | 高 |
| 4 | auto-implement/SKILL.md:121-132 | Phase 5b 知識還流の自動分類 | B+A | 記録基準 3 トリガーは既に rubric。分類側に実例（昇格になった/ならなかった実 feedback）を few-shot 添付 | 中 |
| 5 | auto-implement/SKILL.md:139-141 | バックログ追記対象の選別（「将来改善すべきもの」） | B | 「INFO 指摘か」「変更ファイル外か」「再現手順が書けるか」の YES/NO 化 | 低 |
| 6 | auto-implement/SKILL.md:152-266 | レポート実例 3 本（115 行）が SKILL.md に常駐 | E | references/report-examples.md へ分離（few-shot として優秀、常駐が問題） | 中 |
| 7 | auto-implement/SKILL.md:287-290 | 並列時ファイル競合「影響範囲を推定」 | C+B | Issue 本文からパス抽出→積集合を機械判定、非明示依存のみ「迷ったら順次」rubric | 中 |
| 8 | auto-implement/SKILL.md:390 | 「『だいたい決まってる』は未確定と同じ」— 検知方法なし | B | #1 の rubric に統合（曖昧語検出質問を追加） | 中 |

上位モデル前提 top2: ① Phase 0 の設計確定判定 — 無人実行の唯一の入口ゲートが自由裁量 ② Phase 3 のレビュー統合裁定 — 修正続行か停止かを無人で決める箇所

### close-chat（SKILL.md 304 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | close-chat/SKILL.md:47-60 | Step 2「チャット全体を振り返り」4 カテゴリ抽出 | B+A | カテゴリ別 YES/NO 質問（「結論が出たか」「文書化したか」）+ 実セッションの抽出 OK/NG 例 | 高 |
| 2 | close-chat/references/knowledge-reflux-guide.md:9,13 | 「業界共通の判断軸か→Yes」— センス依存の一問 | A | 還流実績（OSS 還流になった / PJ 固有止まりだった実例）を few-shot 化 | 高 |
| 3 | close-chat/SKILL.md:221-230 | 判断ログの線引き | B+A | 既に基準あり。対象/対象外の実例ペアを 5 組追加すれば標準モデルで安定 | 中 |
| 4 | close-chat/SKILL.md:155-158 | 「CHANGELOG に反映されているか確認」が prose | C | マージ commit subject と [Unreleased] 行の kw 照合スクリプト | 低 |
| 5 | close-chat/SKILL.md:189-269 | Notion 節（約 80 行）が無効 PJ でも常駐 | E | references/ へ分離（200 行以内へ復帰） | 中 |
| 6 | close-chat/SKILL.md:298 | 「次回のセッションで本当に必要か」自問 | B | 「1 ヶ月後に読んで行動できるか」「Issue 化条件に該当しないか」YES/NO | 低 |

上位モデル前提 top2: ① 還流候補の「業界共通か / 複数 PJ 横断か」判定 ② Step 2 の長大セッション振り返り抽出

### weekly-inventory（SKILL.md 351 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | weekly-inventory/SKILL.md:27-28 | 「3 件以上の同趣旨」— クラスタリングが暗黙 | B | ペア判定 rubric（同一トリガー操作か / 同一是正行動か / 同一失敗モードか → 2/3 YES で同趣旨）+ 件数カウントは機械 | 高 |
| 2 | weekly-inventory/SKILL.md:32 | 「テンプレートのデフォルトのまま」判定 | C | 配布テンプレとの diff で機械判定 | 低 |
| 3 | weekly-inventory/SKILL.md:139,150 | 「1 週間以上」「1 ヶ月以上前」が prose | C | MEMORY.md 内日付の抽出＋日付比較スクリプト | 低 |
| 4 | weekly-inventory/SKILL.md:169-170 | 「feedback と brain の記述に乖離がないか」 | B | 「brain 側に対応原則が存在するか」「反例となる追記があるか」の項目別 YES/NO | 中 |
| 5 | weekly-inventory/SKILL.md:181 + references/feedback-compression-rules.md:7-15 | 昇格判定「一般化できる原則に昇華できる」 | A+B | 3 件ルールは機械。昇華可否は過去の昇格済/却下 feedback を few-shot（実物が Memory Index に 16 件ある） | 高 |
| 6 | weekly-inventory/SKILL.md:158 | 「CLAUDE.md に昇格すべきものの提案」— 基準なし | D | knowledge-map 判断フローを premise-check として明示適用 | 中 |
| 7 | weekly-inventory/SKILL.md:283-284 | 「頻繁にブロックされるパターン」— データ源も方法も無指定 | C | guard hook のブロックログを残す仕組み＋回数集計スクリプト（現状は実行不能な prose） | 中 |
| 8 | weekly-inventory/SKILL.md:49-106 | sidekick 未取込チェック bash 57 行が /inventory Step 5 と重複 | E | scripts/ へ共有スクリプト抽出し両スキルから呼ぶ | 中 |

上位モデル前提 top2: ① 「同趣旨」クラスタリング＋原則への昇華（知識パイプラインの心臓部が全部暗黙） ② Step 3a の brain との意味的乖離検出

### inventory（SKILL.md 244 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | inventory/SKILL.md:173-175 | 重複検知「キーワード一致・同一機能への言及」 | C+B | kw/パス一致はスクリプト化、意味的同一のみモデル | 低 |
| 2 | inventory/SKILL.md:212-214 | 「最も優先度の高いタスクの提案」— 基準無定義 | B | rubric（Critical? ブロッカー保持? 経過日数? 他タスクの前提?）で順位付け | 中 |
| 3 | inventory/SKILL.md:97-159 | severity 判定・Critical フラグ書込は既に bash で決定的 | — | 現状維持（**C 化の模範。他スキルの手本**） | — |

### tune（SKILL.md 101 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | tune/references/audit-lanes.md:64-69 | 「トートロジー/弱いアサート」「実装結合で脆い」判定 | C+B | toBeDefined/toBeTruthy/expect 無しは grep パターン集で機械化、「脆い」のみ rubric | 中 |
| 2 | tune/references/audit-lanes.md:75-80 | 「高複雑度・深いネスト」を grep で拾う指示 | C | complexity ツール or ネスト深度カウントスクリプト | 低 |
| 3 | tune/references/audit-lanes.md:90 | severity high/medium/low の付与基準なし | B | 基準表（wall-clock 影響秒数・該当ファイル数の閾値）を schema に併記 | 中 |
| 4 | tune/references/audit-lanes.md:104-110 | 統合の impact 序列 | B+D | impact 推定に定量値（件数×サイズ）ベースの計算式を与え、裁定のみモデル | 中 |
| 5 | tune/references/safety-guardrails.md:51 | バックテスト「テストを実質的に弱めないか」 | D | 「この統合で消えるアサートが捕まえていたバグを挙げよ」の敵対検証を明示ステップ化 | 高 |
| 6 | tune/references/safety-guardrails.md:57-61 | 「削除提案ゼロ」自己検証がチェックリスト | C | findings JSON を delete/削除/remove で grep する機械ゲート | 高 |

上位モデル前提 top2: ① バックテスト＝統合がテストを弱めるかの意味判定（誤ると安全網が実質減る） ② severity/impact 付与 — 標準モデルは全部 medium に潰しがち

### ライフサイクル系横断の DRY 違反

1. **還流 3 分類＋「全 PJ で適用したい判断軸か?」判定が 4 箇所に別文面で存在** — close-chat references/knowledge-reflux-guide.md、weekly-inventory Step 4 + references/feedback-compression-rules.md、auto-implement Phase 5b、rules/knowledge-map.md。判定 rubric と few-shot を単一 reference に集約し全員が参照する形へ。
2. **sidekick バージョンチェック bash が二重実装** — inventory SKILL.md:97-159 と weekly-inventory SKILL.md:49-106（severity フォールバック文面も微妙に相違＝将来の乖離バグ源）。scripts/ へ共有化。
3. **Notion 前提条件チェックが 3 重記述** — close-chat Step 6/6.5、inventory Step 1、weekly-inventory Step 4.5。加えて「同趣旨→3 件→昇格」ラダーが weekly-inventory Step 0a/3b/3c と knowledge-map.md に重複。

---

## 系統3: 運用系スキル + hooks

### release（SKILL.md 160 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | release/SKILL.md:47-52 + references/release-format-spec.md:190-212 | 温度感判定が例の列挙のみ、「迷ったら上位」とモデル読解に委ねる | B | YES/NO rubric 化（stop hook 破壊? guard 無効化? データ喪失? →1 つでも YES=Critical、opt-in のみ?=Enhancement、残り=Standard） | 高 |
| 2 | release/SKILL.md:54-64 | semver bump をモデルが CHANGELOG を読んで提案 | C | [Unreleased] セクション見出し grep で bump を決定するスクリプト | 中 |
| 3 | release/SKILL.md:130-135 + spec:30-32 | 「title prefix・banner・severity マーカー 3 点一致」がモデルの注意力頼み | C | gh release create 直前に draft body を検証する pre-release スクリプト（不一致で fail） | 高 |
| 4 | release/SKILL.md:42-45 | 「[Unreleased] に項目がある」確認が目視 | C | 空判定スクリプト化（backlog 既知の「空チェック必須化」と同件） | 中 |
| 5 | release/references/release-format-spec.md:16 | Title「30 文字以内・キャッチー」が感覚指定 | A | 過去リリース title 3-4 例を spec に few-shot 掲載 | 低 |
| 6 | release/references/release-format-spec.md:122-137 | 「手動手順を書かない」原則が判断規範のみ | B | body への「〜してください」+コマンド共起 grep を検知層に | 中 |

上位モデル前提 top2: ① 温度感判定（severity は下流の取込行動を直接駆動するのに閾値 rubric なし） ② 3 点一致・必須セクションの整合が機械検証なし

### setup（SKILL.md 518 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | setup/SKILL.md:1-518 | 518 行で目標の 2.6 倍。全 Step 常駐 | E | 新規 PJ / 既存 PJ / brain 初期化を references/ に分割 | 中 |
| 2 | setup/SKILL.md:82-123 | ヒアリング回答→yaml 値の変換規則が無い | A | 代表スタック 5 例の回答→yaml 完成形マッピング表を few-shot 掲載 | 中 |
| 3 | setup/SKILL.md:127-145 | settings.local.json の allow/deny をモデルが発明 | A | スタック別 allow/deny テンプレを references に置き選択式に | 高 |
| 4 | setup/SKILL.md:283-297 | .gitignore 追記が「配置したファイル」のモデル追跡依存 | C | 配置済みファイルの存在チェック→対応パターン append のスクリプト化 | 中 |
| 5 | setup/SKILL.md:403-413 | 有効 HARD ルール一覧をモデルがレンダリング | C | CLAUDE.md yaml を読んで表を出力するワンライナー | 低 |
| 6 | setup/SKILL.md:449-490 | Step 1E 現状確認が prose チェックリスト（9 項目） | C | doctor スクリプト 1 本で ✅/❌ 表を機械出力 | 中 |
| 7 | setup/SKILL.md:157-161 | 「スキル活用方針を案内する」が完全に曖昧 | B | 「DB 有無 / UI 有無 / チーム規模」の 3 質問→案内文の分岐表に | 低 |

上位モデル前提 top2: ① ヒアリング自由回答から yaml 全項目を正しく埋める推論 ② allow/deny リストの発明（過剰許可 / 許可漏れが標準モデルで顕在化しやすい）

### adopt-sidekick-update（SKILL.md 461 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | adopt-sidekick-update/SKILL.md:1-461 | 461 行で最大級。bash 断片と対話 UI が単一ファイル常駐 | E | Step 6.4/6.5 の長大 bash を references/ or scripts/ に分離 | 中 |
| 2 | adopt-sidekick-update/SKILL.md:176-179 | 「変更サマリ 2 行」生成がモデル任せ | A | 良いサマリ 2 例（何が変わる / PJ への影響の 2 行型）を few-shot 掲載 | 低 |
| 3 | adopt-sidekick-update/SKILL.md:441 | 「Critical で Y を選ぶ前に内容確認」が Gotcha prose | C | Critical 時は diff 表示を通過必須ステップにするフロー強制 | 中 |
| 4 | adopt-sidekick-update/SKILL.md:239-245 | 6.4a の追記処理がコメント prose（未実装） | C | 抽出→追記までスクリプト完結（判断は Y/n のみ残す） | 中 |
| 5 | adopt-sidekick-update/SKILL.md:24,447 | --all モードが read -r でハング | E | read を引数/env フラグで迂回する auto 経路整備（backlog 既知） | 中 |
| 6 | adopt-sidekick-update/references/skip-record-format.md:99-113 | スキップ記録の整合性チェックが仕様 prose のみ | C | skip-record 読み書きの helper スクリプト化（冪等更新） | 低 |
| 7 | adopt-sidekick-update/SKILL.md:252-269 | 6.4b @import 挿入位置は default N | D | **現状維持が正しい**（機械挿入は誤配置リスク。人手ゲート維持） | 低 |

### news（SKILL.md 125 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | news/SKILL.md:71-80 | prefix→カテゴリ分類が表提示のみでモデル手作業 | C | git log --format + prefix grep でカテゴリ別リスト機械生成（モデルは要約のみ） | 低 |
| 2 | news/SKILL.md:62-68 | DB/API/UI 判定のパス集合がハードコード推測 | C | CLAUDE.md 設定 or PJ 検知でパス集合を解決 | 低 |
| 3 | news/SKILL.md:112-113 | 「ユーザーに見える変化を中心に」「英語は意訳」が感覚指定 | A | 変換前後のサマリ例 1 組を few-shot 掲載 | 低 |

全体として Return Contract 済で劣化リスクは小。

### record-decision（SKILL.md 120 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | record-decision/SKILL.md:17-23 | 次番号を ls 出力からモデルが決定（採番衝突ガードなし） | C | max+1 の 4 桁ゼロ埋めワンライナー（並行 worktree の重複防止） | 中 |
| 2 | record-decision/SKILL.md:25-31 | 判断内容の整理（背景/選択肢/理由の抽出）が言語化能力依存 | D | 真の難所。テンプレ各欄に「良い記入例 1 本」を埋めた exemplar ADR を references に置く | 高 |
| 3 | record-decision/SKILL.md:114-118 | 「仕様レベルのみ」の線引きが規範 prose | B | YES/NO 3 問（複数選択肢から選んだか / 外部から観測可能か / 後から「なぜ」を問われるか）→2 YES で ADR | 中 |
| 4 | record-decision/SKILL.md:69-85 | README 索引の行追記が手作業 | C | 追記スクリプト化 | 低 |

上位モデル前提 top2: ① 判断の構造化（選択肢の復元・却下理由の言語化）＝標準モデルで最も質が落ちる箇所 ② ADR にする/しないの線引き

### token-audit（SKILL.md 143 行）

| # | file:line | 現状 | 分類 | 置換案 | 影響度 |
|---|---|---|---|---|---|
| 1 | token-audit/SKILL.md:64-67 | 検知観点（重い rule / 肥大 / 重複）が「手動判断」と明記 | C | 重複＝同一見出し・同一文のクロスファイル grep、メタ文書判定＝ファイル名リスト化 | 中 |
| 2 | token-audit/SKILL.md:111-123 | 「最も効く削減」の優先度付けがモデル判断 | B | 文字数降順 top-3 を機械提示 +「200 行超か / 常駐必須か」の 2 問で候補判定 | 中 |
| 3 | token-audit/SKILL.md:21-103 | Step 1-3 の計測・cap 読取りは bash + fail-open で決定的 | — | **変更不要（モデル非依存の資産）** | — |

### hooks 資産（既に決定的に守られているもの・変更不要）

- guard-bash.sh: 保護ブランチ push・.env 書込・rm 再帰・prisma db push・gh api write・保護ブランチ向け pr merge を deny（H3/H5/H9）
- guard-db-operation.sh: PRD DB 操作の物理 deny + 接続先の毎回注入（H1/H2/H6）
- guard-commit-message.sh: H15 欠落 commit を機械 deny
- guard-protected-branch-edit.sh: 保護ブランチ上の Edit/Write deny（H5/H9/H12）
- budget-cycle-halt.sh: cap 60%/85% の THROTTLE/PAUSE を Stop 境界で決定的適用
- prompt-reminder.sh: HARD ルール要点の毎プロンプト注入（モデル記憶に依存しない認知層）
- session-start.sh: 7 点検の機械出力
- hook-helpers.sh: PROTECTED_BRANCHES の単一ソース解決
- githooks/pre-commit: PII regex スキャンの物理ブロック

### hook 化候補（prose → 強制層/検知層へ降ろせる検査）

- release フォーマット検証（3 点一致・必須セクション）→ gh release create 前の body lint
- [Unreleased] 空/placeholder 検査 → CHANGELOG lint
- リリースノート手動手順検知 → 命令形+コマンド共起 grep（検知層）
- ADR 採番・索引整合 → 採番スクリプト + README 突合
- setup doctor → 存在確認スクリプト 1 本
- SIDEKICK_VERSION 空検知 → session-start.sh に 1 行追加（既存 [6/7] と同型）
- Critical 取込時の diff 強制 → adopt のフロー必須ステップ化
- SKILL.md 200 行超過検知 → token-audit Step 2 に skills/*/SKILL.md 行数チェック追加
- token-audit 重複検知 → 同一見出しのクロスファイル grep スクリプト

---

## 系統4: 常駐ルール層（rules / brain / CLAUDE.md）

### 解釈依存の原則 top10（操作的定義の案付き）

| # | file:line | 原則 | 標準モデルでのブレ方の予想 | 操作的定義の案 |
|---|---|---|---|---|
| 1 | brain/thinking.md:34 | 70%の確信で動く | 確信度の自己推定は較正されず、過剰確認（停止）か過剰前進の両極に振れる | 「不可逆ブラックリスト（CLAUDE.md §2）に該当しなければ進む」に還元し、%判定を廃止 |
| 2 | brain/thinking.md:35 | 確証 95%未満は断定しない | 「読んだ気」で断定しやすい（plausible-but-wrong） | 「一次ソース（コード/実行結果）を当該セッションで見たか? NO→確度ラベル必須」の YES/NO テスト |
| 3 | brain/thinking.md:24 | 既存活用ファースト | 「最終手段」の閾値がブレ、探索 1 回で新規追加に走る | 新シンボル追加時「既存候補を 2 つ列挙+不採用理由」を出力必須欄に |
| 4 | brain/thinking.md:28 | 安全側に倒す | ロールバック不能な中間状態を安全と誤認 | 「元に戻すコマンドを 1 行で書けるか? 書けなければ承認必須扱い」テスト |
| 5 | brain/thinking.md:25 | 意図のないコードは書かない | 「意図」の有無は主観判定 | code-quality §1「変更全行になぜを説明」と統合し、diff 行単位の説明欄を rubric 化 |
| 6 | code-quality.md:22 | 「シニアエンジニアが過剰に複雑と言わないか」 | ペルソナ想像テストはモデル能力差が最大に出る | 定量 proxy に置換: 新規抽象は呼び出し 2 箇所以上 / ネスト≤3 / 1 関数≤40 行 |
| 7 | context-economy.md:38 | trivial-gating | 「trivial」判定がブレて fan-out 過剰 or 必要な難所まで縮退 | 機械判定: 変更ファイル数≤N + diff 行数≤M + 全パスが docs/**・*.md → trivial（script 化可） |
| 8 | context-economy.md:33 | セッション ~60% で先回り /compact | cap% はモデルの体感で読めず発火が運任せ | rate_limits テレメトリで閾値超過時のみ機械通知（budget-gate PR3 と同方向） |
| 9 | context-economy.md:58 | 難所は必ず上位モデル（不変条件） | 「難所か」の判定自体を下位モデルに委ねる自己言及 | **難所を閉集合で列挙**（設計判断/root-cause/矛盾裁定/セキュリティ/最終 judge）+ 判定不能時は上位既定 |
| 10 | knowledge-map.md:92-93 | 3 件ルール + クリティカル class は N=1 昇格 | 「致命クラス」該当判定がブレ、昇格漏れ or 濫用 | 致命 = {データ喪失, 本番影響, セキュリティ, guard 無効化} の 4 カテゴリ列挙に限定 |

次点: task-management.md:16「他人が拾えるか」（3 問 YES/NO 化: 再現手順が書ける / 受入条件 1 行 / 自分以外が着手可能 → 2/3 で Issue）、CLAUDE.md ゲート 2 確度表示（「数値・仕様・API 名を含む主張には必ずラベル」の発火条件化）。

### セルフレビュー Step（brain §2）の外部化候補

| Step | 現状 | 外部化形態 | 案 |
|---|---|---|---|
| Step 1 現状分析ファースト | prose。「最も違反しやすい」と自認済み | rubric | 提案テンプレに「調査したファイル: file:line」必須欄。空なら提案を出せない形式に |
| Step 2 母数の最大化 | prose | rubric | 出力フォーマットで「案≥2 + 各却下理由」を構造強制 |
| Step 3 NG フィルター照合 | prose。feedback を毎回想起する前提 | script | feedback タイトル索引を grep で自動提示する helper |
| Step 4 一貫性チェック | prose。4 ソース照合をモデル記憶に依存 | script+rubric | ADR タイトル一覧・rules 一覧の自動注入（retrieve 支援）。裁定のみモデル |
| Step 5 自問 3 点 | prose | rubric | チェックボックス 3 点を出力テンプレに埋め込み |
| Step 6 コードレビュー観点 | prose チェックリスト | script/hook | DRY=重複検出器、影響範囲=参照元 grep 数を /review fast-gate の決定的検査に前置。「意図の可読性」のみモデル判定に残す |

### 常駐 footprint 実測

| ファイル | 行数 | 指摘 |
|---|---|---|
| CLAUDE.md | 232 | **200 行目安を自ら超過**。HARD 一覧とブラックリスト表が同内容を二重掲載（H2/H5/H9/H3/H12 が両表に）→片方を対応表参照に |
| rules/git-strategy.md | 152 | 最大 rule。後半 80 行（Worktree 手順）は手順書 = skill/references へ retrieve 化候補。H15 が CLAUDE.md と重複 |
| rules/knowledge-map.md | 125 | レイヤー表が documentation.md と重複。昇格ラダーが task-management.md とも重複気味 |
| rules/pii-prevention.md | 104 | path-scoped 済 ✅。ただし bash 関数 40 行が githooks/pre-commit と実装重複→script 参照化で本文半減可 |
| rules/task-management.md | 96 | NOTION_ENABLED=false（既定）時、後半 ~60 行が dead weight。Layer 2 節を .example へ退避すれば常駐 36 行 |
| rules/context-economy.md | 59 | context-management.md と **compact 閾値の数値不一致**（~60% 先回り vs 50%検討/70%超過）→統合 or 数値統一 |
| rules/code-quality.md | 47 | GUIDE・レビュー時観点 → paths: 付与 or /review-code references/ へ移して常駐から外せる |
| rules/oss-doc-authoring.md | 43 | path-scoped 済 ✅ |
| rules/context-management.md | 33 | context-economy と統合候補 |
| rules/naming-conventions.md | 33 | path-scoped 済 ✅（模範） |
| rules/database.md | 31 | H1 が CLAUDE.md と重複。DB 無し PJ では dead → 設定ゲートで外せる構造が無い |
| rules/documentation.md | 25 | knowledge-map.md と表重複 → 統合候補 |
| rules/deploy-strategy.md | 18 | DB 無し PJ では dead。paths: 付与候補 |
| rules/workflow.md | 11 | 問題なし |
| .claude/brain/thinking.md（PJ brain） | 25 | 問題なし |
| 個人 brain（~/.claude/brain/thinking.md） | 108 | 環境固有節が auto-memory の reference と役割重複気味（個人環境側の整理） |
| brain/thinking.md（OSS テンプレ） | 130 | 仕様上ロード対象外だが、保守者環境では @import で実質常駐（+130 行） |
| .claude/docs/skill-agent-design.md | 236 | 常駐ではないが 200 行超過。状態表を references 化候補 |

常駐合計（概算・保守者環境）: CLAUDE.md 232 + brain 3 層 263 + rules 非 scoped 597 = **約 1,092 行**（path-scoped 180 行は該当パス時のみ）。

### HARD ルール vs hook の対応漏れ

- **H10/H11（STG 時の PR 経路制限）: hook なし** — `gh pr create --base` の base/head 検査を guard-bash に追加すれば決定化可能（STG_ENABLED 時のみ発火）
- **H13（worktree 作成→MEMORY.md 記録の順序）: hook なし** — `git worktree add` 検知の PostToolUse reminder で認知層は機械化可能
- **H14（DB マイグレーション並行禁止）: hook なし** — guard-bash は prisma migrate に警告を出すが、Active Work の並行状態は照合しない
- **H7/H8 と AUTO_MODE の関係（要裁定）** — guard-bash.sh:65 で `AUTO_MODE="${SIDEKICK_AUTO:-true}"`（**既定 true**）。:128 で git push、:178 で gh pr merge が auto-approve される。H7/H8 は「必ずユーザー確認」の HARD。意図的例外なら ADR-0026（AUTO_MODE 既定）で明記が必要
- **H1 の部分カバー** — guard-db-operation はコマンドパターン検知に依存。任意スクリプト経由の DB アクセスは検知外（既知の設計制約）
- **H9 の Bash 迂回** — guard-protected-branch-edit は Edit/Write のみ対象。Bash リダイレクト書込は commit 時点では止まらない（push 時に Guard 2 が止めるため実害は限定的）
- カバー済み（モデル非依存資産）: H3/H5/H9/H12/H15/H2/H6/PII は物理 deny または強制層あり。H4/H7/H8 は警告 + permission dialog 委譲（承認型として妥当。ただし上記 AUTO_MODE 論点あり）
