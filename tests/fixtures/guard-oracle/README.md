# guard 回帰オラクル — STG ルーティングガードの凍結期待値

guard-bash.sh **Guard 11**（STG PR 経路 = H10/H11）+ Guard 10（executor 警告）フォールスルーの
回帰ベースライン。`cases.jsonl` の 26 ケース（ルーティングマトリクス 18 + 敵対 8）は、
**hook への stdin JSON → deny/allow の観測結果を実走で確定**したもの（読み判断による期待値は 1 件もない）。

- 凍結日: 2026-07-05 / 検証対象: `.claude/hooks/guard-bash.sh`（main c6f2163 時点）
- 全 26 ケースを `replay.sh` で実走し 26/26 一致を確認してから凍結

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

## 検証（リプレイ）

```bash
bash tests/fixtures/guard-oracle/replay.sh <リポルート>   # 26/26 PASS で exit 0
```

CI への配線・他 guard（push / .env / rm 系）への拡張は別ステップ（実装 wave）。

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
