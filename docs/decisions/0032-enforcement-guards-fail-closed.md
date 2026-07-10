# ADR-0032: enforcement 層は fail-closed、advisory 層は fail-open + 検知

## ステータス

採用（2026-07-10）。実装済み（`.claude/hooks/` の 4 enforcement guard に fail-closed ブートストラップ、`hook-helpers-budget.sh` 新設、`session-start.sh` に enforcement 健全性チェック）。前提は ADR-0002（ブラックリスト方式）・ADR-0024（budget-gate）。

## 背景

`.claude/hooks/` の 12 hook のうち 9 本が、共有ライブラリを `source "$(dirname "$0")/hook-helpers.sh"` で読み込む。`deny` / `allow_with_context` / `get_db_pattern` / `get_protected_branches` はこの lib で定義される。この source が失敗した場合（ファイル欠落・破損・パス解決失敗）、`set -e` がないため bash は継続し、以降 `deny` は未定義となる。deny 判定は「JSON を stdout に出力して成立」する仕様のため、`deny` が呼べない = **判定が出ない = allow**。結果、enforcement 層が無言で丸ごと fail-open（何も止まらない）に倒れる。9 本が同一 lib に依存するため単一障害点でもある。

fail-open 自体は「hook は advisory（認知補助）」という前提なら妥当だが、下流が `Bash(*)` を自動承認する運用にすると人間の確認ステップが消え、guard hook が本番 DB 書き込み前の唯一の防壁（load-bearing）になる。この状態で lib が壊れると本番書き込みが素通りする。enforcement を名乗る層が「読み込めない = 通す」に倒れているのは思想の反転で、enforcement なら fail-closed が筋である。

加えて `get_db_pattern` は parse miss 時に空文字を返すため、`PRD_DB_PATTERN` が設定されていたのに設定が壊れた（configured then drifted）場合と、そもそも未設定（never configured）だった場合を区別せず、後者でも PRD 書き込み保護が静かに消える。

## 決定

1. **enforcement 4 guard は fail-closed**: `guard-bash.sh` / `guard-db-operation.sh` / `guard-commit-message.sh` / `guard-protected-branch-edit.sh` は、helper lib を完全に読み込めなければ deny する。実装は「EOF sentinel + subshell probe」:
   - `hook-helpers.sh` 末尾に `_CCS_HELPERS_LOADED=1` を置く。ファイル途中の syntax error は初期の関数を定義しても sentinel 行に到達しないため、sentinel の有無が「全体がパースされたか」の証明になる（`command -v deny` では途中破損を見逃す — deny は前半で定義済みのため）。
   - source を **subshell の probe** で先に走らせる。lib 内の top-level `exit` や syntax error が親 guard を巻き添えに終了させると、guard は非ゼロ exit で終わる = non-blocking hook error = fail-open になる。probe を subshell に隔離することでこれを防ぎ、probe 成功時のみ本 source する。
   - probe 前に `unset _CCS_HELPERS_LOADED`（親環境から継承した sentinel が load 失敗を隠すのを防ぐ）。source は `>/dev/null 2>&1` で probe し、破損 lib の stdout ゴミが deny JSON に混入するのを防ぐ。deny 前に stdin を drain する。
   - deny メッセージは**復旧すべきファイル名を出さない**。「enforcement を人間が復元せよ・guard を書き換えて回避するな」と誘導する。lib を「直せ」と案内すると、誤動作した LLM に骨抜きの手順を与えるため。

2. **advisory hook は fail-open + 検知**: `session-start.sh` / `remind-worktree-memory.sh` / `budget-cycle-halt.sh`（Stop）/ `prompt-reminder.sh` は lib load 失敗でも動作を止めない。特に Stop hook を block に倒すと利用者が離脱できなくなる（可用性事故）。代わりに `session-start.sh` に enforcement 健全性チェック `[8/8]` を追加し、lib load 失敗（= 全 Bash/Edit が deny される状態）と DB-pattern drift を毎セッション可視化する（検知層）。

3. **budget パースを別ライブラリに分離**: rate-cap 読み取り（`prompt-reminder.sh` と `budget-cycle-halt.sh` の重複 ~60 行）を `hook-helpers-budget.sh` に集約する（DRY）。ただし `hook-helpers.sh` には統合しない。budget は ADR-0024 の閾値・capturer schema に連動する高 churn コードで、これを「壊れると全 enforcement guard が fail-closed する」ファイルに同居させると、budget の typo が全 Bash/Edit ロックアウトを招く（churn × fail-closed = 事故頻発）。fail-closed の core は小さく安定に保つ。budget lib は advisory 側 2 hook のみが fail-open で source する。分離時、両 hook の grep フォールバック挙動の差（prompt = jq 空なら grep / Stop = jq 不在時のみ grep）を `mode`（loose / strict）引数で完全保存する — malformed JSON を jq が拒否し grep が拾うケースで、prompt は budget 行を出し Stop は silent（fail-open）を維持する。

## 選択肢と却下理由

- **A. `command -v deny` チェックのみ**: ファイル途中の syntax error では `deny` は前半で定義済みのため検知できない（実測で確認）。sentinel + probe が必要。
- **B. sentinel チェックのみ（subshell probe なし）**: lib 内 top-level `exit` が親 guard を巻き添えに終了させ、判定行に到達しないまま非ゼロ exit = fail-open になる（実測で確認）。probe の subshell 隔離が必要。
- **C. 全 hook を fail-closed**: Stop hook を block に倒すと利用者が離脱不能になる。可用性事故で、data-safety の要求と釣り合わない。advisory は fail-open が正しい。
- **D. budget を hook-helpers.sh に統合**: DRY は満たすが、高 churn コードを fail-closed gate の core に同居させ、事故的全ロックアウトのリスクを恒常化する。別ファイル分離（採用）が core を小さく保つ。
- **E. enforcement 層の完全な信頼性保証（自己改竄も封じる）**: 本 ADR のスコープ外（下記「既知の天井」）。

## 既知の天井（このADRが封じないもの）

sentinel は「ファイルが完全に load された」ことの証明であって「`deny` が deny する」ことの証明ではない。したがって次は封じられない:

- **loaded-but-tampered**: feature ブランチ上では `.claude/hooks/hook-helpers.sh` や `settings.json` 自体を編集でき（H12 で作業は feature ブランチに集約されるため、保護ブランチ編集ガードは発火しない）、`deny(){ exit 0; }` に書き換えれば sentinel を通過したまま全 guard が骨抜きになる。sidekick 本体は hooks を日常的に編集するため、`.claude/hooks/**` 編集の全ブランチ hard-deny は開発ワークフローと衝突する。
- **BASH_ENV / `BASH_FUNC_*` による関数注入**: hook を起動する bash プロセスの環境に `BASH_ENV` で readonly な no-op `deny` を仕込むと、lib の `deny` 再定義が readonly で失敗し（error は `2>/dev/null` に吸われる）、sentinel は正当に set され、bootstrap を通過して `deny` が no-op のまま bypass する（実測で確認）。`unset` は変数汚染にしか効かず、関数注入は塞げない。

これらは「load 失敗（事故）」とは別クラスの信頼境界問題で、根本対策は hook shell 向けの env-scrub（`BASH_ENV` / `ENV` / `BASH_FUNC_*` の除去）— ハーネス側の責務で hook の手の届かない範囲にある。無人実行の OS 隔離（sandbox + env-scrub）の一部として別途扱う。本 ADR は load-failure の fail-open のみを封じる。

## 検証

- fail-closed ブートストラップ: 4 guard × { 欠落 / 途中 syntax error / top-level exit / stdout ゴミ / env 継承 sentinel } の全条件で deny、healthy + benign stdin では通過を実走確認（`tests/fixtures/guard-oracle/bootstrap-test.sh`・25 PASS / 0 FAIL）。既知の天井（BASH_ENV + readonly deny）は XFAIL として記録し、封じた時に SEALED へ昇格する。
- 回帰: 既存 guard oracle 42 ケース replay を healthy lib で green 維持（42 PASS / 0 FAIL）。
- budget 分離: `prompt-reminder.sh` / `budget-cycle-halt.sh` の出力を分離前（origin/main）と pct = { 30, 60, 70, 85, 90 } で byte-exact 一致を確認。malformed JSON（jq 拒否・grep 一致）で prompt = budget 行 / Stop = silent の意図的差分を保存。PAUSE re-entry marker が 2 回目の Stop を block しないことを実走確認。
