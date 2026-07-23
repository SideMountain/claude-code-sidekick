# guard 回帰オラクル — STG ルーティング・.env 書き込みガードの凍結期待値

guard-bash.sh **Guard 11**（STG PR 経路 = H10/H11）+ Guard 10（executor 警告）フォールスルー、
**Guard 4.5**（`.env` 書き込み = H5）、および **Guard 5.5/5.6 + cmd executor**（`git worktree
remove` の node_modules junction 事故防止 / Windows 再帰削除 / `cmd /c` ラップ payload）の回帰
ベースライン。`cases.jsonl` は計 53 ケース = Guard 11 STG 経路 26（ルーティングマトリクス 18 +
敵対 8）+ Guard 4.5 `.env` 書き込み 16（v0.13.1 追加）+ Guard 5.5/5.6/cmd executor 11。
いずれも **hook への stdin JSON → deny/allow の観測結果を実走で確定**したもの
（読み判断による期待値は 1 件もない）。

- 凍結日: 2026-07-05（Guard 11 26 ケース）/ 2026-07-06 追加（Guard 4.5 16 ケース）
  / 2026-07-23 追加（Guard 5.5/5.6/cmd executor 11 ケース）
  / 検証対象: `.claude/hooks/guard-bash.sh`
- 全 53 ケースを `replay.sh` で実走し 53/53 一致を確認してから凍結

## 形式（cases.jsonl・1 行 1 ケース）

```json
{"id":"G11-01", "description":"...", "hook":".claude/hooks/guard-bash.sh",
 "env":{"SIDEKICK_STG_ENABLED":"true"}, "stdin":{"tool_input":{"command":"..."},"cwd":"/tmp"},
 "expected":{"decision":"deny|allow_context|allow_silent", "output_contains":"H10"}}
```

- `env`: hook に渡す環境変数。`SIDEKICK_STG_ENABLED` が Guard 11 の設定 override（空オブジェクト = env 未設定で CLAUDE.md フォールバックを検査）
- `expected.decision`: `deny`（stdout JSON `permissionDecision:deny`）/ `allow_context`（allow + additionalContext）/ `allow_silent`（出力なし・exit 0）
- `expected.output_contains`: stdout に含まれるべき部分文字列（H10/H11 の理由文・警告文）
- `known_gap: true`: 現行実装の**既知の検知漏れを観測値のまま**凍結したケース（下記）
- `{{REPO}}`（`stdin` 内のプレースホルダ）: `replay.sh` が実行時にリポルートへ置換する。
  fixture パス（例: Guard 5.5 の疑似 Worktree `wt-junction-sim/`）を clone 位置に依存せず
  参照するための機構。`wt-junction-sim/node_modules/` は `.gitignore`（`node_modules/`）で
  コミットできないため、`replay.sh` が実行時に自己プロビジョンする

## 検証（リプレイ）

```bash
bash tests/fixtures/guard-oracle/replay.sh <リポルート>          # 53/53 PASS で exit 0
bash tests/fixtures/guard-oracle/bootstrap-test.sh <リポルート>  # 25/25 PASS で exit 0
```

- `replay.sh`: **healthy** な helper lib に対する guard の deny/allow 期待値（`cases.jsonl` 53 ケース）。
- `bootstrap-test.sh`: helper lib を**破損させた**ときに 4 enforcement guard が fail-closed で deny するかを検査（Issue #103 / ADR-0032）。SEALED（欠落 / 途中 syntax error / top-level exit / stdout ゴミ / env 継承 sentinel）は deny を assert。CEILING（BASH_ENV + readonly `deny` の関数注入）は現状 bypass する既知の天井で XFAIL 記録 — env-scrub で封じたら SEALED へ昇格する。

CI への配線・他 guard（push / rm 系）への拡張は別ステップ（実装 wave）。

## 更新ポリシー（回帰ベースラインとしての意味）

- **deny → allow に変わる差分は弱体化**（REVIEW.md §2 の無条件 BLOCKER 相当）。リプレイの FAIL を
  「fixture が古い」で片付けず、ガード変更そのものを疑う
- allow → deny への変化は検知拡大（正当な強化）。**ガード変更と同一 PR で** 該当ケースの expected を
  更新し、変更理由をコミット本文に記す
- ケース追加は新 ID の追記。既存ケースの `stdin` の書き換えは禁止（ケースの同一性が失われる）

## 既知の検知漏れ（known_gap・観測値で凍結）

- **G11-A3**: `printf '%s' '--base main --head feature/x' | xargs gh pr create` —
  フラグ列全体がクォートで包まれると `--base` 抽出（先頭が空白/行頭であることを要求）に掛からず、
  Guard 10 の executor 警告（allow_context）どまり。deny には至らない。
  ガード側の是正は guard 修正 wave の対象（ガード機構変更 = 難所 cat4・ladder 適用）。是正が入ったら
  本ケースの expected を deny に更新する（上記ポリシーの「検知拡大」パス）

## 決定性の注意

- 全ケース `--head` を明示している。`--head` 省略時の Guard 11 は `git branch --show-current` に
  フォールバックするため、実行時のブランチに依存する（オラクルには含めない）
- **G11-12**（env 未設定 → CLAUDE.md フォールバック）は、リポの `CLAUDE.md` テンプレート既定
  `STG_ENABLED: false` を前提とする。STG を有効化した PJ では期待値が変わる（このケースのみ）
- hook はコマンドを実行しない（grep 判定のみ）。リプレイにネットワーク・副作用はない
