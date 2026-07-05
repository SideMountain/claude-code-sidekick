# RC — root-cause 分析（§8 難所 cat2）ケース

回答形式（各ケースごと）:

```
id: RC-XX
root_cause: C1|C2|C3|C4
rationale: <1-2 行。症状のどの観測事実が他候補を棄却するかを明示>
```

判定基準: 提示された症状・観測事実だけから、最も整合する真因を 1 つ選ぶ。観測事実と矛盾する候補を消去できているかを測る。
**参照禁止**: `.claude/hooks/`・`.claude/skills/` の実装ファイル・git 履歴・`docs/plans/`。

---

## RC-01: 連結形だけガードを素通りする

症状: コミットメッセージ必須フィールドを検査する PreToolUse ガードで、

- `git commit -m "fix: ..."`（direct 形・フィールド欠落）→ **deny される**(検査が機能)
- `git add -A && git commit -m "fix: ..."`（連結形・同じくフィールド欠落）→ **silent に allow される**（検査されない）

観測事実: hook の stdin JSON パースはどちらの形でも成功しており、デバッグ出力で COMMAND 変数にコマンド全文が入っていることを確認済み。どちらのコマンドにも `--amend` は含まれない。

真因候補:

- **C1**: 発火判定の正規表現が行頭 `git commit` のみマッチし、連結形では先頭が `git add` なので不発
- **C2**: quote 除去処理が `-m "..."` のメッセージと一緒に `git commit` 部分まで削っている
- **C3**: jq パースが連結形の `&&` で失敗し、COMMAND が空になって fail-open している
- **C4**: `--amend` 除外ロジックが連結形を誤って amend と判定してスキップしている

## RC-02: standard リリースが lint で誤 fail する

症状: release notes の 3 点一致（severity マーカー / title prefix / body banner）を検査する決定的 lint で、severity=standard の notes が `[FAIL] banner — standard だが body に **CRITICAL** banner が残っている` で exit 1 になる。

観測事実:

- body を目視確認したが、blockquote（`>` 行）の banner は存在しない
- body の Changes 節に、過去リリースの再掲として `- **CRITICAL** 相当の guard 迂回修正を含む v0.x.y を取り込み` という箇条書き（行頭 `- `）がある
- 引数の severity は standard で正しく渡っている / title に prefix 語は含まれない

真因候補:

- **C1**: notes 作成者が banner 行を消し忘れており、実際に blockquote banner が残っている
- **C2**: banner 検査が blockquote 行に限定しない位置非依存 grep で、Changes 本文の `**CRITICAL**` 強調を banner と誤認している
- **C3**: 呼び出し側が severity 引数に critical を渡している（引数の取り違え）
- **C4**: blockquote の入れ子（`> >`）が banner 検査の正規表現を壊している

## RC-03: rebase が index.lock で失敗する

症状: WSL 環境で `git rebase` を実行すると `fatal: Unable to create '.../index.lock': File exists` で毎回失敗する（間欠的でなく決定的に再現）。

観測事実:

- `ps aux | grep git` で他に走行中の git プロセスは存在しない
- 該当 index.lock の mtime は 3 日前
- 3 日前に WSL が応答不能になり、ホスト OS ごと強制再起動した経緯がある
- 同リポの worktree 構成は変更しておらず、従来この配置で正常に動いていた

真因候補:

- **C1**: 並行して走っている別の git プロセス（エディタの git 連携等）が lock を保持している
- **C2**: 強制再起動でクラッシュした git プロセスが残した stale な lock ファイル
- **C3**: worktree の gitdir 設定不整合で、別 worktree の index.lock を誤って参照している
