# REL — release 温度感判定（R10）ケース

回答形式（各ケースごと）:

```
id: REL-XX
severity: Critical|Enhancement|Standard
reason: <1-2 行>
```

判定基準（rubrics R10・上から順に判定し最初に該当した severity を採用）:
1. Critical（1 つでも YES）: ガード/hook の無効化・迂回可能性の修正 / データ喪失リスクの修正 / 保護機構の既定値変更 / セキュリティ修正
2. Enhancement: 全変更が opt-in または新規追加のみ（既存挙動の変更ゼロ）
3. Standard: 上記以外すべて

---

## REL-01

リリース内容: 「guard-bash.sh の正規表現バイパス 6 件を修正（クォート・変数展開・executor 包みで検知をすり抜けられた）+ budget-gate の Stop hook 配線を追加」

## REL-02

リリース内容: 「rules 2 本（database / deploy-strategy）を path-scoped 化して常駐から外し、Worktree 手順・Layer2 プロトコルを遅延ロード doc へ移設。ルール本文の削除はなし（配置とロードタイミングのみ変更）」

## REL-03

リリース内容: 「新規 opt-in の stack pack を 1 つ追加（`STACK_PACK: none` の既定 PJ には無影響・既存ファイルの変更ゼロ）」
