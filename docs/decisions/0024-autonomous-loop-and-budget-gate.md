# ADR-0024: 自律ループと budget-gate（rate-cap 内の長時間・自律稼働）

## ステータス

採用（2026-06-24、設計を決定）。PR2 = 本 ADR + capturer（データ面）。enforcement hook（強制面）の配線は WSL 実機検証を経た follow-up（決定 6）。前提ドクトリンは ADR-0023。

## 背景

ADR-0023 で文脈経済の原則を定めた。本 ADR はその中の「O(n²) を断つ」「lossy には検知層」「複利の効く所から」を、**自律ループ（`/auto-implement` 等）を rate-cap の中で長時間・安定に回す**具体設計へ落とす。

検証で判明した実データの制約（[ADR-0023 実データ源]）:

- cap の `used_percentage`/`resets_at` は statusLine の stdin JSON `rate_limits` でのみ読める。**hook の stdin には来ない**。
- `rate_limits` は **全製品横断の合算 quota**、**render 時ポーリング**更新（イベント駆動でない＝鮮度ラグ）、**Pro/Max のみ**、fresh session/API-key では不在。
- 単一グローバルファイルに capture すると、並行 worktree では**最後に render したセッションに上書き**される（`%` はグローバルなので有効だが、per-session 値は誤る）。

## 決定

### 決定 1: 自律ループは「状態を外部化した有界・再開可能な短サイクルの連鎖」にする

ループの記憶を会話履歴でなく **disk の progress ledger**（決定 + why / 残タスク / 次の一手）に置き、サイクル境界で context をリセットする。会話履歴の O(n²) コストを毎サイクル O(小) に戻す。再開は ledger の read だけで済む（フル履歴の再投入が不要）。1 サイクル = 1 検証可能な最小単位（テスト緑で都度証明）。

### 決定 2: capturer リレー（データ面）— hook が rate_limits を読めないため

ccs が薄い **capturer**（statusLine の stdin から `rate_limits` だけを抜き、正準ファイル `~/.claude/.cache/ccs-rate-limits.json` に書く）を配る。スキーマは ccs 所有で安定（`{schema, captured_at, session_id, five_hour:{pct,resets_at}, seven_day:{pct,resets_at}}`）。`rate_limits` の知識（jq パス）はこの 1 箇所だけに閉じ、全フィールド `// null` 防御。**per-session 値はここに入れない**（合算 quota の `%` のみがグローバルに安全だから）。これが強制面の唯一のデータ橋。

### 決定 3: budget-gate は Stop 境界での段階制御を核とする（PreToolUse throttle は採らない）

`five_hour` を主・`seven_day` を上書き制約として severity を決める:

- **< 60% NORMAL**: 通常。
- **60–85% THROTTLE**: fan-out 抑制・難所以外は上位 model を避ける・出力簡約。**振る舞いの誘導であって作業はブロックしない**。
- **> 85% PAUSE**: 次の **Stop 境界**で自律ループを停止し、ledger + commit を残してから `resets_at` まで休止（`seven_day` が拘束条件なら週次優先トリアージに切替）。実行中の単一ツールは殺さない。

**Stop 境界を核に据える理由**: データが最も新鮮で、ledger + commit を中断なく完了できる唯一の自然な区切り。**PreToolUse 毎ツール throttle と hard な model 切替は採らない**（ポーリングで分単位 stale になりうる・model 強制切替は advisory 止まりで信頼性が低い）。

### 決定 4: 認知の可視化は閾値超過時のみ（通常時は汚染ゼロ）

残 cap を Claude に見せる cognition 行（prompt 注入）は **THROTTLE 以上のときだけ**出す。通常時（大半のターン）は何も注入しない＝常駐汚染を作らない（ADR-0023「不要文脈を渡さない」と整合）。

### 決定 5: 精度の聖域と fail-safe

- throttle が削るのは**幅**（fan-out・上位 model・冗長出力）であって**正しさ**ではない。難所は「安く今やる」でなく「休止して回復後に上位 model で」。
- **安全ガード（DB 書込・保護ブランチ・.env・rm -rf 等）は budget 状態から独立**し、budget hook より**先に**走る。budget hook は安全ガードを短絡しない。
- データ不在・stale・パース不能は **fail-open**（NORMAL 扱い）。`rate_limits` 不在（API-key / fresh / 旧版）で誤ってブロックしない。`captured_at` が閾値より古ければ NORMAL に落とし検知ノートを出す。`now > resets_at` は「リセット済（回復）」とみなす。

### 決定 6: 段階配布（検知 → capturer → 強制）と /setup gating

- **PR1（配布済）**: `/token-audit` = 検知のみ・fail-open。
- **PR2（本 ADR）**: capturer（データ面）+ 本設計。capturer は安全に dogfood 可能。
- **enforcement hook（強制面・follow-up）**: budget-cycle-halt（Stop）と cognition 行は、**WSL での hook 実機検証を経てから**配線する。`/setup` は **capturer が新鮮なファイルを書いていることを検証してからのみ**強制を有効化する。検証できないなら強制は無効のまま、検知レポータは常時動かして**休眠を可視化**する（「効いているつもり」を防ぐ）。

## 影響

- 新規: `.claude/statusline/ccs-rate-capture.sh`（capturer）、本 ADR。
- follow-up: `.claude/hooks/budget-cycle-halt.sh`（Stop）、`prompt-reminder.sh` への条件付き budget 行、`/setup` の capturer 検証 + 配線、progress ledger を使う `/auto-implement` 改修。
- 非 Next/非自律 PJ は無コスト（capturer 未配線なら検知が休眠を報告するだけ）。

## 代替案と却下理由

- **単一グローバルファイルに per-session 値も入れる**: 却下。並行 worktree で別セッションに上書きされ誤る（実証済）。capture は合算 `%` のみ。
- **PreToolUse で毎ツール throttle / hard model 切替**: 却下/保留。ポーリング鮮度で stale、model 強制は advisory 止まり。render cadence を実測してから再検討。
- **hook から rate_limits を直接読む**: 不可（検証済・hook stdin に無い）。capturer リレー必須。
- **強制を即配布**: 却下。WSL hook 実機未検証 + capturer 不在の下流で「守っているつもりで無力」になる。検知先行・強制は gating 後。
