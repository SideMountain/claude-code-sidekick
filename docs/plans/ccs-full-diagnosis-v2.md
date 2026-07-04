# ccs 全量診断 v2 — 6 軸監査 + v1 消化状況突合

> 診断日: 2026-07-05。[v1 = ccs-model-independence-diagnosis.md](ccs-model-independence-diagnosis.md)（2026-07-04・約 60 判断ポイント）の後継。
> 方法: 司令塔がリポの一次ソースを直接 Read する全量監査（委任 audit 不使用）。guard の挙動主張は実走で確認したものに「実走確認」と付記する。
> 軸: ①北極星（ADR-0018）②3層仕組み化（認知→強制→検知）③知識複利 ④文脈経済（ADR-0023）⑤モデル非依存（ADR-0027/0028）⑥配布完全性（ADR-0001/0009/0014/0015）。

---

## 1. 読了範囲（coverage・silent cap なし）

**直読（全文）**: 実働 13 SKILL.md + 全 references/（review scoring-guide・official-skills / release format-spec / adopt skip-record 除く=下記）+ review-fitness.sh + official-freshness.sh / REVIEW.md / hooks 9 本全文 + detect-hard-spot.sh + githooks/pre-commit + settings.json / stack pack（ARCHITECTURE.md・README・fitness README・scaffold README・system-map SKILL/methodology/adapters README・run-fitness.js・canonical-counts.js）/ .claude/templates/ 全 5 ファイル / .claude/docs（worktree-guide・knowledge-reflux・skill-agent-design・task-db-layer2）/ docs/migrations（README・review-6to1-adapter）/ ADR 0009・0014・0015・0018・0025・0026・0027・0028 / drafts（rubrics.md R1-R10・exemplars.md）/ lifecycle.md 英日 / CHANGELOG [Unreleased] / tests/fixtures/judgment-corpus README。

**読んでいない（明示・非 silent）**: stack pack の JS 内部実装（checks.js・route-enumerator.js・adapters 実体・scaffold.js・template.html — `verify.js` / `verify-adapters.js` の fixture 自己検証があるため doc + CLI 入口の直読で足りると判断）/ adopt references/skip-record-format.md / ADR 0001-0008・0010-0013・0016・0019-0024（要旨は常駐 rules・v1・他文書経由で保持）/ docs/cron-setup-guide・playwright-setup-guide・migrations/memory-md-to-auto-memory.md（レガシー手順書）/ README 英日は counts の spot-check のみ（v0.13 直前に #79 で全面鮮度是正済み）。

---

## 2. 総括（6 軸判定）

| 軸 | 判定 | 一行根拠 |
|---|---|---|
| ①北極星 | **良** | 3 動詞 + 配管の構造は skills/hooks 全面に一貫。lifecycle.md の輪 7/8 の「開」も誠実に明記 |
| ②3層仕組み化 | **良・穴 2 件** | 強制層は大幅強化（guard-bash 11 guards・force-flag・budget 2 hooks）。ただし guard-commit-message の連結形迂回（実走確認）と guard-db-operation の設定ドリフト（§4 P1-1/P1-2） |
| ③知識複利 | **良** | R5/R6/R7 + few-shot の単一ソース化（knowledge-reflux.md）が完成。4 箇所重複解消を実地確認 |
| ④文脈経済 | **中** | WS6 で 979→788 行。ただし SKILL.md 200 行超 4 本（setup 560 / adopt 502 / weekly-inventory 379 / close-chat 304）と budget パース 60 行の意図的重複が残存 |
| ⑤モデル非依存 | **中の上** | 中核（R1-R9 配線・min()・force-flag・凍結 corpus）は完了。周辺 rubric/few-shot（release R10・discover 敵対ステップ・タスク分解 exemplar 等）は**原案あり・未配線** |
| ⑥配布完全性 | **要対処** | #79 で hooks/scripts/docs は閉じたが、**REVIEW.md・settings.json（hooks 配線）・.claude/templates/ が依然 /adopt の全カテゴリ非対象**（§4 P0）。ADR-0015 完結性原則に未達 |

---

## 3. v1 消化状況 突合表

凡例: ✅消化 / 🔶部分（or 原案あり未配線）/ ❌未消化 / ➖対象消滅・現状維持が正 / 【B】既存 Backlog に行き先あり。

### 3.1 系統 1: review 系（44 項目）— 実質完了

| v1 | 状況 | 現在の担い手 |
|---|---|---|
| review #1 スコープ判定 | ✅ | アダプタ化で fitness 前置 + 公式 /code-review 委譲（SKILL.md Step 2/3） |
| review #2 観点間矛盾 | ✅ | auto-implement Phase 3 + context-economy §8 L2（多視点 3 票） |
| review #3 最終判定 rubric | ✅ | Step 5 が scoring-guide.md を明示 Read・min() 一本化 |
| review #4 scoring-guide 未配線 | ✅ | 同上 + REVIEW.md §3 と同一ルール相互明記 |
| review #5 /verify 条件化 | ✅ | R9（Step 4・ランタイム表面 YES/NO） |
| review #6 review*/ 変更で全観点 | ➖ | 観点 fan-out 自体が廃止（アダプタ化）で対象消滅 |
| review #7 200 行超過 | ✅ | 107 行 |
| review-code #1-#9 | ➖/✅ | stub 化で個別指摘は消滅。内容の移設: #5 DB 設計→REVIEW.md §1c + §8 難所 cat1 ✅ / #6 破壊的 KW→review-fitness.sh Check1 ✅ / #7 水平展開→§1k ✅ / #8 認可→§1a + §8 cat4 + /security-review ✅ / #9→min() ✅ / #2 既存パターン・#3 YAGNI・#4 複雑度→公式 /code-review の一般観点に委譲 ➖ |
| review-test #1-#7 | ➖/✅ | #6 モック忠実性→§1j ✅ / #1 テスト欠落→§2 WARN 定義に規範化 🔶（機械マッピングは未実装）/ #3 弱アサート→/tune lane③ に残存 🔶 / 残→公式委譲 ➖ |
| review-ops #1-#6 | ➖/✅ | #1 外部依存→§1h ✅ / #2 レース→§1g ✅ / #3 空 catch→fitness Check3 ✅ / #4 PII→§1i + pre-commit ✅ / #5 ロールバック→§1c 🔶 / #6→公式委譲 ➖ |
| review-design #1-#6 | ➖/🔶 | #4 a11y→fitness Check2 ✅ / #3 トークン grep→§1e 規範のみ 🔶（P-B 憲章④で決定的化予定【B】）/ #1 アンカー例→❌【B ④ exemplar anchor】/ #5#6 ラベルズレ→消滅 ➖ |
| review-spec #1-#6 | ➖/✅ | #3 仕様突合 2 段手順→§1b-3 に verbatim 実装 ✅ / #1 API 契約→§1c ✅ / #5→fitness ✅ / #4 ADR grep 前出し→§1b-1 は prose 🔶 / #2 エラー形式実例→core は未 🔶（stack pack H2 エンベロープのみ）/ #6→消滅 ➖ |
| DRY #1 破壊的 KW 4 重 | ✅ | review-fitness.sh に単一化（ヘッダに経緯明記） |
| DRY #2 越境の鏡像重複 | ✅ | stub 化で消滅 |
| DRY #3 判定分散・rubric 未配線 | ✅ | min() を REVIEW.md §3 ⇔ scoring-guide で単一化 |

### 3.2 系統 2: ライフサイクル系（41 項目）— 中核消化・周辺残

| v1 | 状況 | 備考 |
|---|---|---|
| discover #1 探索の固定スクリプト化 | ❌ | Step 1 は prose リストのまま |
| discover #2 ギャップ分析 methodology | ❌ | Step 3 は「整理する」構造のまま（premise-check 未配線） |
| discover #3 却下理由 kw-grep | ❌ | Step 4 冒頭 checkbox のまま |
| discover #4 推奨の敵対ステップ | 🔶 | §8 R3 反証プロンプトが一般形で存在・discover SKILL 未配線（§4 P2-1） |
| discover #5 比較表省略 3 条件 | ✅ | Step 4 に 3 条件 + 省略時も却下理由必須 + Gotcha |
| discover #6 タスク分解 few-shot | 🔶 | drafts/exemplars.md §B に OK/NG 原案あり・references/ 未配置 |
| discover #7 スコープ膨張 | 🔶 | Step 5 checkbox + Gotcha の明示確認質問 |
| auto-implement #1-#8 | ✅×8 | R1 rubric 7 問 + 機械 grep / Q6 機械 / verdict 無再判断 / R7 単一ソース / 5c YES/NO / report-examples 分離（393→180 行）/ パス積集合 / 曖昧語 grep。加えて v1 に無い R4-impl・force-flag 前置・R8 を新設 |
| close-chat #1 Step2 抽出 few-shot | ❌ | 4 カテゴリ表 + 抽出ルールのみ |
| close-chat #2 還流判定 | ✅ | knowledge-reflux.md R7 + few-shot |
| close-chat #3 判断ログ線引き実例 | ❌ | 基準 prose のまま |
| close-chat #4 CHANGELOG kw 照合 | ❌ | Step 5.5 目視のまま（§4 P0-3 で実害が顕在化） |
| close-chat #5 Notion 節 80 行常駐 | ❌ | 304 行のまま・Step 6/6.5 インライン【B SKILL 分割】 |
| close-chat #6 バックログ自問 | ❌ | prose のまま |
| weekly-inv #1 同趣旨クラスタ | ✅ | R5 参照（2/3 YES） |
| weekly-inv #2 テンプレ既定判定 | ❌ | 「デフォルトのまま」prose |
| weekly-inv #3 日付比較 | 🔶 | Step 0.5 は日数計算あり / Step 2b「1 ヶ月以上」は prose |
| weekly-inv #4 brain 乖離 | ❌ | Step 3a prose |
| weekly-inv #5 昇格 few-shot | ✅ | R6 + few-shot コーパス |
| weekly-inv #6 CLAUDE.md 昇格基準 | ❌ | Step 2c prose |
| weekly-inv #7 hooks ブロック実績 | ❌ | Step 5c は依然データ源なしの実行不能 prose（guard 側にログ蓄積なし）（§4 P2-4） |
| weekly-inv #8 バージョンチェック二重 bash | ❌ | Step 0.5 ⇔ inventory Step 5 の別実装が残存 |
| inventory #1 重複検知 / #2 優先度 rubric | ❌❌ | 【B WS5 二次】 |
| inventory #3 severity 機械判定 | ➖ | 現状維持（模範）。severity マーカー第一ソース + title fallback を確認 |
| tune #1 弱アサート grep 集 / #2 複雑度 / #3 severity 基準 / #4 impact 計算式 / #6 削除ゼロ機械ゲート | ❌×5 | 【B WS5 二次（tune references の B/C）】lane プロンプトは LLM 指示のまま |
| tune #5 バックテスト敵対検証 | 🔶 | safety-guardrails「是正前のバックテスト」+ §8 R3 消失テスト（一般形）あり・tune からの明示参照なし |
| DRY #1 還流 4 箇所 | ✅ | knowledge-reflux.md 単一ソース（4 参照元を実地確認） |
| DRY #2 sidekick チェック bash 二重 | ❌ | 上記 weekly-inv #8 と同件 |
| DRY #3 Notion 前提 3 重 | ❌ | close-chat Step6/6.5・inventory Step1・weekly-inv Step4.5（各短文・実害小） |

### 3.3 系統 3: 運用系 + hooks（36 項目）— release/setup/adopt はほぼ未消化（行き先は確定済み）

| v1 | 状況 | 備考 |
|---|---|---|
| release #1 温度感 rubric | 🔶 | drafts/rubrics.md **R10 が原案として存在（配線先 = release SKILL.md と明記済み）だが未配線**。凍結 corpus REL 3 件が測定器として存在 |
| release #2 semver スクリプト / #4 [Unreleased] 空判定 / #5 title few-shot / #6 手動手順 grep | ❌×4 | 【B release lint・[Unreleased] 空チェック必須化】 |
| release #3 3 点一致 pre-release 検証 | ❌ | 【B hook 化候補】。spec は「必ず一致させる」prose のまま |
| setup #1 518 行分割 | ❌ | **560 行に増加**（budget-gate 検証 Step 5.8 等の追加）【B SKILL 分割】 |
| setup #2-#7 | ❌×6 | ヒアリング→yaml few-shot / allow-deny テンプレ / .gitignore script / HARD 表レンダ / 1E doctor / スキル案内分岐 — いずれも未着手【B ⑤ hook 化候補（setup doctor）】 |
| adopt #1 461 行分離 | ❌ | **502 行に増加**（#79 のカテゴリ追加で正当な増分を含む） |
| adopt #2 サマリ few-shot / #3 Critical diff 必須 / #6 skip-record helper | ❌×3 | 【B ⑤】 |
| adopt #4 6.4a 追記処理 | 🔶 | 検出までは bash 具体化（heredoc パターン）・追記実行は prose コメント |
| adopt #5 --all read ハング | ❌ | Gotcha に明記・auto 経路未整備【B】 |
| adopt #7 6.4b default N | ➖ | 現状維持が正（v1 の判断どおり） |
| news #1-#3 / record-decision #1・#3・#4 | ❌ | 影響度 低〜中。record-decision #2（exemplar ADR）は 🔶 drafts/exemplars.md §D（ADR-0025 アンカー方式）原案あり・未配線 |
| token-audit #1 重複検知 | 🔶 | Step 2 の大半は機械化済・クロスファイル重複 grep のみ未 |
| token-audit #2 優先度 | ❌ | 【B WS5 二次】 |
| token-audit #3 | ➖ | 現状維持（+ Step 3 rate_limits 読取りが PR1/2 で完成） |
| hook 化候補 9 件 | ❌×9 | 全件未着手・全件【B ⑤ post-7/8 wave】に行き先あり |
| HARD 漏れ: H10/H11 | ✅ | guard-bash Guard 11（executor 前置・セグメント分割・実機 18+8 ケース検証済み） |
| HARD 漏れ: H13 | ✅ | remind-worktree-memory.sh（PostToolUse・認知層） |
| HARD 漏れ: H14 hook | ❌ | 【B ⑤】Active Work 照合 hook なし（auto-implement R1-Q7 が無人経路のみカバー） |
| HARD 漏れ: AUTO_MODE 既定 true | ✅ | ADR-0026 で既定 false 化（guard-bash.sh:71 で確認・実機 3×3 検証記録あり） |
| HARD 漏れ: H1 部分カバー / H9 Bash 迂回 | ➖ | 既知の設計制約として妥当（H1 は §4 P1-2 の設定ドリフトが別途あり） |

### 3.4 系統 4: 常駐ルール層 — top10 は半分消化・残りは操作的定義 wave 待ち

| v1 top10 | 状況 | 現在の担い手 |
|---|---|---|
| #2 95% 断定 | ✅ | CLAUDE.md ゲート 2 発火条件（事実忠実性ゲート）+ R4-impl（編集直前） |
| #7 trivial-gating | ✅ | auto-implement R8（4 条件の機械判定） |
| #8 60% compact | ✅ | prompt-reminder の budget cognition 行 + budget-cycle-halt（閾値 60/85・v1 提案そのもの） |
| #9 難所閉集合 | ✅ | §8 閉集合 5 項目 + detect-hard-spot force-flag + ladder L1-L4（ADR-0028） |
| #10 致命クラス 4 分類 | ✅ | knowledge-reflux.md R6（閉集合明記・拡張禁止） |
| #1 70% 確信 / #3 既存活用 / #4 安全側 / #5 意図 / #6 シニア proxy | ❌×5 | 【B ⑤ 操作的定義 wave】 |
| セルフレビュー Step1-6 外部化 | ❌ | 【B ⑤】（Step1 の一部は R4-impl・discovery 直読 feedback として部分実装） |
| footprint 表 | 🔶 | WS6 消化: task-management Layer2 退避 ✅ / git-strategy worktree 分離 ✅ / database・deploy path-scoped ✅ / compact 閾値統一 ✅。見送り（意図的）: CLAUDE.md 二重掲載【B WS6 残】/ knowledge-map⇔documentation 統合【B】/ pii bash 参照化【B】/ code-quality paths ❌ |

### 3.5 集計

約 121 項目（v1 の番号付き指摘 + 横断）中: **✅消化 41 / 🔶部分・原案未配線 14 / ❌未消化 51 / ➖対象消滅・維持 15**。未消化 51 のうち **約 8 割は既存 Backlog（⑤ post-7/8 wave・WS5 二次・SKILL 分割・release lint）に行き先が確定済み**で、行き先未定の実質的な新規宿題は少ない。v1 の中核（min() 配線・還流単一ソース・R1/R8/R9・難所 ladder・force-flag）は完了しており、残りは「周辺スキルの rubric/few-shot 配線」と「release/setup/adopt の機械化」に集中している。

---

## 4. v2 新規発見（v1 に無い指摘・全て当該セッションで一次ソース確認済み）

### P0 — 次リリース前に対処（配布完全性・#79 と同型）

1. **REVIEW.md が `/adopt-sidekick-update` の全カテゴリ非対象** — adopt Step 2 の diff 対象（rules/skills/brain/hooks/scripts/docs/PJ_MIG/stack pack）のどれにもルートの `REVIEW.md` が含まれない（SKILL.md 全文 grep で確認）。`/setup` Step 1E が初回配置するのみで、以後 ccs 側の PJ 規範（severity 定義・min() ルール・§1 観点）更新が下流に永久に届かない。fitness スクリプトは [skills] で届くのに規範だけ古くなる drift。PJ 調整済みファイル（条件ブロック削除等）なので blind overwrite は不可 — **PJ-protected + diff 案内（6.4c 型）または条件ブロック保持 merge（6.4a 型）のカテゴリ追加**が正解。ADR-0015 完結性原則（adopt 実行だけで完結）に未達。
2. **`.claude/settings.json`（hooks 配線 + deny list）が `/adopt` 非対象** — settings.json は 8 hooks の配線そのもの（SessionStart / UserPromptSubmit / PreToolUse×4 / PostToolUse / Stop）。[hooks] カテゴリで .sh 本体は届くが**配線は届かない**ため、fork 後に ccs が hook を追加すると下流ではファイルだけ存在して発火しない silent no-op になる（実例: v0.12 の Stop=budget-cycle-halt、remind-worktree-memory の PostToolUse は fork 時期によっては未配線のまま）。detect-hard-spot.sh 自身が `settings*.json` をガード機構（難所 cat4）に分類しており、ccs の自己認識でも enforcement 構成材。permissions は PJ 拡張されうるので **hooks キーのみ同期提案する partial merge**（CLAUDE.md 6.4a 型）が必要。
3. **CHANGELOG [Unreleased] に #79（adopt の HOOKS/SCRIPTS/DOCS カテゴリ新設 = 配布ブロッカー修正）のエントリが無い** — [Unreleased] 全文 grep で確認（該当語ゼロ）。このままだと次リリースのノート（/release Step 3 は CHANGELOG から Changes を転記）から Critical 相当の変更が漏れる。追記案: `### Fixed — **/adopt-sidekick-update の配布カバレッジ拡張（配布ブロッカー修正）**: hooks 9 本（.claude/hooks/・.claude/githooks/）・共有決定的検査（.claude/scripts/）・遅延ロード doc（.claude/docs/）・skills の scripts//templates/ が一切配布対象外だった穴を是正。[hooks]/[scripts]/[docs] カテゴリを新設し、.sh の実行権限復元（chmod + update-index）とネストパス mkdir -p に対応。`

### P1 — 早期に対処（3層仕組み化の穴）

1. **guard-commit-message.sh が連結コマンドを素通り（実走確認）** — 正規表現（:33）が行頭 `(cd …)? git commit` のみマッチするため、最頻出の `git add -A && git commit -m "…"` 形では H15 検査が発火しない（direct 形= deny / chained 形= silent allow を実走で確認）。guard-bash と同じセグメント分割（`;` `&&` `||` で分割して各セグメント検査）で閉じられる。品質系 HARD なので severity は中（認知層 prompt-reminder は毎ターン残る）。
2. **guard-db-operation.sh が STG_DB_PATTERN / PRD_DB_PATTERN を CLAUDE.md から読まない** — :40-41 でスクリプト内ハードコード空文字。CLAUDE.md Project Configuration に両パターンを設定しても**強制層（H1/H2/H6 の物理 deny）は発火しない**。PROTECTED_BRANCHES は `get_protected_branches`（hook-helpers）で CLAUDE.md から読む設計であり非対称。さらに下流がスクリプト直編集で設定する現運用は、adopt [hooks] の blind overwrite で clobber される（pre-commit の PII カスタマイズと同型だが Gotcha 未記載）。**`get_db_patterns` を hook-helpers に追加して CLAUDE.md yaml を単一ソース化**するのが対称解。
3. **`.claude/templates/` が /adopt 非対象** — /setup 再実行時に fork 時点の古いテンプレ（Issue テンプレ・labels.yml 等）を配り続ける。影響は限定的（テンプレは初期配置用）だが、カテゴリ 1 行の追加で閉じる。
4. **setup Step 2c が deprecated の review-code を参照** — 「DB を使わない PJ では review-code の DB 観点をスキップ」（SKILL.md:160）。/review + REVIEW.md 体制では文言が stale（次マイナーの stub 撤去で完全に空振りになる）。

### P2 — 機会があれば

1. **discover に難所 ladder / force-flag が未配線** — discover は R2 難所 1 号（設計判断）の入口だが、SKILL.md は §8 ladder・detect-hard-spot・R3 敵対ステップ（v1 #4）に言及しない。auto-implement には配線済みで非対称。対話スキルなので常駐 rules の暗黙適用に頼る設計も成立するが、Step 4（推奨提示）前の「推奨案を落とす理由を 1 つ」だけでも明示配線する価値がある。
2. **prompt-reminder.sh ⇔ budget-cycle-halt.sh の rate-file パース約 60 行が重複** — prompt-reminder ヘッダ自身が「並行編集中のため統合 deferred（follow-up 候補）」と明記。並行編集が収束した現在は hook-helpers への統合が可能。
3. **scoring-guide.md 末尾「STG 自動マージの条件（将来）」** — 未配線の構想記述。害はないが、min() 単一ソースの文書に将来構想が同居しており、分離（Backlog/ADR 側へ）候補。
4. **weekly-inventory Step 5c「hooks ブロック実績」は依然実行不能** — v1 #7 のまま。guard 側に deny ログ蓄積（例: `~/.claude/.cache/ccs-guard-log`）を足さない限り、この Step は毎回空振りする。⑤ wave の hook 化候補と同時に解消するのが自然。
5. **corpus README が参照する rubric 集（drafts/rubrics.md）が「Phase 0 原案」ラベルのまま常設参照になっている** — R10（release 温度感）等の未配線 rubric と、配線済み rubric（R1-R9）の状態差が原案 doc 内で判別できない。配線状態の注記または配線済み分の削除（単一ソース化）を検討。

---

## 5. 推奨アクション（行き先つき）

| # | アクション | 種別 | 行き先 |
|---|---|---|---|
| 1 | adopt に REVIEW.md（PJ-protected 扱い）+ settings.json（hooks キー partial merge）+ .claude/templates/ カテゴリを追加 | P0 | **新規・次リリース前**（#79 の続編。Critical 相当） |
| 2 | CHANGELOG [Unreleased] に #79 エントリを追記（§4 P0-3 の文案） | P0 | 新規・小 |
| 3 | guard-commit-message のセグメント分割対応 + guard-db-operation の CLAUDE.md 読取り化 | P1 | 新規（ガード変更 = 難所 cat4 → §8 ladder 適用で実装） |
| 4 | setup Step 2c の stale 参照修正 | P1 | stub 撤去リリースに相乗り |
| 5 | release R10 配線 / discover 敵対ステップ + exemplars §B / record-decision exemplar §D 配線 | P1-P2 | 既存 Backlog ⑤ wave に統合（原案は drafts に既在＝配線のみ） |
| 6 | SKILL.md 200 行超 4 本の references/ 分割 | P2 | 既存 Backlog（SKILL 分割・WS6 合流） |
| 7 | budget パース重複の hook-helpers 統合 / guard deny ログ + weekly-inv 5c 実効化 | P2 | 既存 Backlog ⑤ wave |

**v1 の残未消化（§3 の ❌ 51 件）は本表 5-7 と既存 Backlog（⑤ post-7/8 実装 wave・WS5 二次・release lint・adopt --all）で全件カバーされることを確認した。行き先のない宿題は §4 P0/P1 の新規 4 件のみ。**
