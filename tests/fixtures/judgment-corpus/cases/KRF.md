# KRF — 知識還流判定（R5/R6/R7）ケース

回答形式は各ケースに記載。判定基準: `.claude/docs/knowledge-reflux.md`（R5 同趣旨 2/3・R6 昇格 3/4 + 致命クラス閉集合・R7 還流 3 分類）。

---

## KRF-01（R7 分類）

feedback: 「WSL 環境では vitest の既定 pool（forks/threads）が worker 起動タイムアウトを起こす。`--pool=vmThreads` なら完走する」

質問: R7 の 3 分類（OSS 還流候補 / 個人 brain / PJ 固有）のどこに置くか。

```
id: KRF-01
classification: OSS|personal-brain|pj-specific
reason: <1-2 行>
```

## KRF-02（R6 昇格判定）

feedback: 「動作確認のつもりでマージコマンドを実行してしまい、本番相当ブランチへの誤マージが発生しかけた（push 直前に人間が気付いて停止）」。同趣旨の feedback はこれが初回（N=1）。

質問: 昇格候補として提示すべきか。

```
id: KRF-02
promote: YES|NO
reason: <1-2 行。適用した判定ルールを明示>
```

## KRF-03（R5 同趣旨判定）

feedback A: 「diff 全体を確認せず commit し、意図しない一時ファイルが混入した」
feedback B: 「PR 本文の変更概要が実際の diff と不一致のまま PR を作成した」

質問: この 2 件は「同趣旨」か。

```
id: KRF-03
same_gist: YES|NO
criteria: <R5 の 3 基準それぞれの YES/NO>
```
