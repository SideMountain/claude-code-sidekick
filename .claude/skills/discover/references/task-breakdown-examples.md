# タスク分解の few-shot（OK / NG 例）

`/discover` Step 5・`/auto-implement` から参照する、タスク分解の few-shot 実例集。
出自: `docs/plans/model-independence-drafts/exemplars.md` §B を下流配布向けに汎用化（PJ 非依存の題材に置換）。
狙いは題材ではなく**分解の粒度**を示すこと — 完了条件が実行可能 / 影響範囲が列挙済み / 1 タスク = 1 検証可能単位。

---

## OK 例

> 1. ユーザー一覧に名前・メール部分一致の検索フィルタを追加
>    - 完了条件: `GET /api/users?q=foo` が name / email に foo を含むユーザーだけ返す。テスト `search returns only matching users` が green
>    - 影響: `app/api/users/route.ts`（クエリパラメータ処理）/ `lib/users/queries.ts`（where 句追加）
>    - DB 変更: なし（既存インデックスで対応）

**要点**: 完了条件が実行可能（叩けるエンドポイント + 通るテスト名）。影響ファイルが列挙済み。1 タスク = 1 検証可能単位。

## NG 例（と直し方）

> ✗「検索を使いやすくする」 — 観測不能（何をもって完了か不明）。→「検索結果に name / email 部分一致を含める。`search returns only matching users` が green になる」に具体化する。
> ✗「検索 API を作ってフォームも直してテストも足す」 — 仕様判断（API 契約）と実装と別機能追加が 1 タスクに混在。→「①API 契約を決める ②実装 ③テスト追加」に 3 分割し、既存契約を変える場合は移行期間（両対応 → 切替）を挟む。
