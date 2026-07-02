# ADR-0025: budget-gate の Stop hook 実配線

## ステータス

Proposed（2026-07-02、草案）。前提は ADR-0024（自律ループと budget-gate の設計）。本 ADR は「強制面（enforcement hook）の配線」という follow-up 論点だけを扱い、実配線・既定変更は人間の承認と実機検証を経てから行う。

## 背景

ADR-0024 は budget-gate を「Stop 境界での段階制御」として設計し、段階配布（検知 → capturer → 強制）を定めた。現時点で配布済みなのは検知（`/token-audit`）と capturer（`ccs-rate-capture.sh`）までで、強制面は未配線である。`settings.json` の `"Stop": []` は空で、budget 状態を読んで自律ループを Stop 境界で停止させる hook は存在しない。

強制を配線する前に決めるべき論点が残っている。budget hook は「rate-cap の実データ」に依存するが、そのデータは hook stdin に来ず capturer リレー経由でしか読めない（ADR-0024 決定 2）。データが stale・不在なら誤発火のリスクがあり、逆に fail-open を徹底すると「効いているつもりで無力」になりうる。

## 論点

1. `"Stop": []` に budget-cycle-halt hook を配線するか。配線するとして、発火条件（`five_hour`/`seven_day` の閾値）と停止の粒度（次サイクルを開始しない／実行中ツールは殺さない）をどう固定するか。
2. capturer が新鮮なデータを書けているかを、どの時点で・誰が検証するか（`/setup` gating か、hook 内の鮮度チェックか、両方か）。
3. WSL 実機で Stop hook が期待どおり発火・冪等・fail-open するかの検証をどう担保するか。

## 選択肢

- **A. 配線しない（現状維持）**: 検知レポータ（`/token-audit`）のみで運用し、停止は人手。安全だが「長時間・自律稼働を rate-cap 内で安定に回す」という ADR-0024 の主目的が未達のまま。
- **B. 無条件で配線**: `"Stop"` に hook を入れ、閾値超過で常に停止。データ stale/不在時の誤発火リスクが高く、capturer 未配線の下流で沈黙破綻する。ADR-0024 決定 6 に反する。
- **C. gating 付きで配線（推奨）**: hook は入れるが、(1) capturer が鮮度基準（`captured_at` が閾値内）を満たすときだけ強制を有効化し、満たさなければ NORMAL に fail-open して検知ノートで「休眠」を可視化、(2) `/setup` が capturer の新鮮な書き込みを検証してからのみ強制を配線する。閾値・粒度は ADR-0024 決定 3 を踏襲（60–85% THROTTLE / >85% PAUSE、Stop 境界で ledger+commit 後に休止）。

## 推奨

**C**。ADR-0024 の段階配布・fail-open・精度の聖域の原則をそのまま強制面に落とす。安全ガード（DB 書込・保護ブランチ・.env・rm -rf）は budget 状態から独立に先行させ、budget hook はそれらを短絡しない。

## 検証手順（WSL 実機・配線前の必須ゲート）

1. capturer 単体: statusLine stdin の模擬 JSON（`rate_limits` 有／無／古い `captured_at`）を流し、正準ファイルが期待スキーマで書かれる／`// null` 防御が効くことを確認。
2. Stop hook 単体: 正準ファイルを NORMAL / THROTTLE / PAUSE 相当に差し替え、Stop イベントの模擬入力で (a) NORMAL・データ不在・stale は fail-open（停止しない）、(b) PAUSE は次サイクルを開始しない JSON を返す、を確認。冪等性（同一状態で複数回発火しても副作用が増えない）も確認。
3. 安全ガード非短絡: PAUSE 状態でも保護ブランチ push / .env 変更 / rm -rf が従来どおり deny されることを確認（budget hook が先行ガードを飛ばさない）。
4. 統合: `/auto-implement` を短い ledger サイクルで回し、閾値超過時に ledger+commit を残して Stop 境界で停止し、`resets_at` 後に再開できることを確認。

## 影響

- 配線時に変更が想定されるファイル: `.claude/settings.json`（`"Stop"`）、新規 `.claude/hooks/budget-cycle-halt.sh`、`prompt-reminder.sh`（THROTTLE 以上のときのみ cognition 行）、`/setup`（capturer 検証 + gating）、`/auto-implement`（progress ledger 運用）。
- 本 ADR 段階ではコードは変更しない。検証手順を満たし人間が承認した時点で、別 ADR で「採用」に更新し配線する。
- 非自律 PJ は無コスト（capturer 未配線なら検知が休眠を報告するだけ）。
