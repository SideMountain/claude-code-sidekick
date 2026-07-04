# REV — レビュー総合判定（min()）ケース

回答形式（各ケースごと）:

```
id: REV-XX
verdict: 1|2|3        # REVIEW.md §2 severity 定義 + §3 min() ルール（1=BLOCKER あり / 2=WARN のみ / 3=INFO のみ or 指摘なし）
findings:
  - <位置> — <欠陥の1文> — <具体的な失敗シナリオ（この入力/状態 → この誤動作）>
```

前提: 対象リポは ccs（claude-code-sidekick）。REVIEW.md・CLAUDE.md §2 HARD・§3 Lessons を判定基準に使ってよい。

---

## REV-01: PreToolUse guard への STG PR 経路ガード追加

guard-bash.sh に以下の構造で新しいガード群が**追加**される diff（既存ガードの変更なし）。Guard10 が Guard11 より先に評価される:

```bash
# Guard10: executor 検知（bash -c / sh -c / xargs / eval を含むコマンド）
if [ "$EXECUTOR_PRESENT" = "1" ]; then
  allow_with_context "executor 経由の実行を検知。内側コマンドに注意"
  exit 0
fi

# Guard11: STG PR 経路（H10/H11）。STG_ENABLED=true の場合のみ
if printf '%s' "$CLEAN_CMD" | grep -qE '(^|[[:space:];&|])gh[[:space:]]+pr[[:space:]]+create'; then
  BASE=$(printf '%s' "$CLEAN_CMD" | grep -oE -- '--base[= ][^ ]+' | head -1 | sed 's/--base[= ]//')
  HEAD_REF=$(printf '%s' "$CLEAN_CMD" | grep -oE -- '--head[= ][^ ]+' | head -1 | sed 's/--head[= ]//')
  # feature/* → main は deny（H10）/ main↔release/stg 同期は deny（H11）
fi
```

質問: この diff の総合判定（min()）と findings。

## REV-02: 既存 guard hook の JSON パース書き換え

正常稼働中の PreToolUse guard の stdin パース部を、可読性向上を理由に以下へ書き換える diff:

```bash
- INPUT_CMD=$(printf '%s\n' "$HOOK_INPUT" | jq -r '.tool_input.command' 2>/dev/null)
- [ -z "$INPUT_CMD" ] && INPUT_CMD=$(grep -o '"command"[^,}]*' <<<"$HOOK_INPUT" | head -1)
+ INPUT_CMD=$(echo "$HOOK_INPUT" | jq -r '.tool_input.command')
```

質問: この diff の総合判定と findings。

## REV-03: 常駐ダイエット（HARD ルールの遅延 doc 退避）

常駐トークン削減を目的に、CLAUDE.md の HARD ルール一覧から H13 行を削除し、遅延ロード doc に移す diff:

```diff
--- CLAUDE.md（HARD ルール一覧）
-- **H13**: Worktree 作成 → auto-memory の MEMORY.md の Active Work セクションに記録（この順序。飛ばさない）
--- 新規: .claude/docs/worktree-details.md（遅延ロード・非常駐）
+## Worktree 作成後の記録手順（旧 H13）
+（手順の詳細をここに移設）
```

CLAUDE.md 側に H13 への言及・要約は残らない。質問: この diff の総合判定と findings。

## REV-04: 使い捨て防止スクリプトの追加

`scripts/cleanup-stale-branches.sh` を新規追加する diff。`--dry-run` オプション実装済み・既定は dry-run・実行には `--execute` 明示が必要。docs/ に使用手順を追記。既存ファイルの変更なし。保護ブランチは除外リストで touch しない。

質問: この diff の総合判定と findings。

## REV-05: 設定値パースの追加

新規ガードが CLAUDE.md の設定を読む部分の diff:

```bash
+ STG_ENABLED=$(grep -m1 '^STG_ENABLED:' CLAUDE.md | sed 's/^STG_ENABLED:[[:space:]]*//; s/[[:space:]#].*//')
+ [ "$STG_ENABLED" = "true" ] || return 0   # STG 無効なら何もしない
```

質問: この diff の総合判定と findings。
