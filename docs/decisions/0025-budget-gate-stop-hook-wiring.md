# ADR-0025: budget-gate の Stop hook 配線

## ステータス

Accepted（2026-07-02）。実装済み（`.claude/hooks/budget-cycle-halt.sh` を `settings.json` の `Stop` に配線）。前提は ADR-0024（自律ループと budget-gate の設計）。

## 背景

ADR-0024 は budget-gate を「Stop 境界での段階制御」として設計し、段階配布（検知 → capturer → 強制）を定めた。検知（`/token-audit`）と capturer（`ccs-rate-capture.sh`）は配布済みで、本 ADR は残る強制面（Stop hook）の配線を扱う。

budget hook は rate-cap の実データに依存するが、そのデータは hook stdin に来ず capturer リレー経由の正準ファイルからしか読めない（ADR-0024 決定 2）。データが stale・不在なら誤発火のリスクがあり、逆に無条件 fail-open だと「効いているつもりで無力」になりうる。この二律をどう捌くかが配線の設計論点になる。

## 決定

`budget-cycle-halt.sh` を `Stop` に配線し、gating 付き強制とする（ADR-0024 決定 3 / 決定 5 の踏襲）。

1. **段階制御**: 正準ファイルの rate 使用率に応じ、<60% は無出力、60–85% は助言のみ（THROTTLE）、>85% は Stop 境界で ledger+commit を促して次サイクルを休止（PAUSE）。実行中ツールは殺さない。
2. **gating + fail-open**: capturer が鮮度基準（`captured_at` が閾値内）を満たすときだけ強制を有効化する。不在・stale・パース失敗・`// null`（API キー運用等で rate 情報なし）は NORMAL に fail-open し、検知ノートで「休眠」を可視化する。jq 不在時は grep フォールバックで同じ判定に落とす。
3. **再入ガード**: 公式仕様に `stop_hook_active` 相当のフィールドが無い環境でも無限ブロックを起こさないよう、session_id 別マーカーで「同一セッションで一度だけ block」を保証する。フィールドが供給されれば併用する。
4. **安全ガードの独立性**: budget 状態は安全ガード（保護ブランチ push / `.env` / `rm -rf` / PRD DB）を短絡しない。これらは budget hook と無関係に常時 deny される。
5. **出力形式**: 公式準拠の top-level `{"decision":"block","reason":...}` と共通 `systemMessage` を使う。

## 選択肢と却下理由

- **A. 配線しない（検知のみ）**: 停止は人手。安全だが「rate-cap 内で長時間・自律稼働する」という ADR-0024 の主目的が未達。
- **B. 無条件で配線**: 閾値超過で常に停止。データ stale/不在時の誤発火が高く、capturer 未配線の下流で沈黙破綻する（ADR-0024 決定 6 に反する）。
- **C. gating 付きで配線（採用）**: 鮮度を満たすときだけ強制、満たさなければ休眠を可視化して fail-open。段階配布・精度の聖域の原則をそのまま強制面に落とす。

## 検証（WSL 実機）

サンプル JSON を stdin 投入し allow/deny/warn の判定のみ観測（破壊コマンドは非実行）。全ケース exit 0・jq で JSON 妥当性確認済み:

- 正準ファイル不在 / 使用率 30% / `// null` / 破損 stdin → 無出力（fail-open）
- 使用率 72.5% fresh → `systemMessage` で THROTTLE 助言のみ
- 使用率 91% fresh 初回 Stop → `{"decision":"block", ...ledger+commit...}`
- 同一セッション 2 回目 → block せず休止ノートのみ（再入ガード）／別セッション → 再び 1 回 block
- `captured_at` が 2 時間前（stale）→ NORMAL 化 + capturer 未配線検知ノート
- `resets_at` 経過 → 回復扱い・無出力
- `seven_day`=90 / `five_hour`=30 → seven_day 拘束で PAUSE
- jq 不在（PATH 制限）→ grep フォールバックで block→note→silent
- E2E: statusLine 形式 JSON → capturer → 正準ファイル → Stop hook で block 発火・2 回目 allow

## 影響

- `.claude/settings.json`（`Stop` 配線）、新規 `.claude/hooks/budget-cycle-halt.sh`。
- capturer 未配線・非自律 PJ は無コスト（検知ノートが休眠を報告するだけ・停止しない）。
- follow-up（本 ADR の範囲外）: ADR-0024 決定 6 の「`/setup` が capturer の鮮度を検証してから強制を有効化する」gating を setup 側に足すと、既定配線と検証ステップの整合がより厳密になる。現状は hook 内の鮮度チェック + fail-open で安全側を担保している。
