---
name: review
description: "統合レビュー（アダプタ）。決定的 fitness 前置 → 公式 /code-review（REVIEW.md 注入）→ min() 総合判定。PJ 規範（HARD照合・ADR整合・破壊的変更・PII・a11y）は REVIEW.md に集約。コミット前 / PR 作成前に実行。"
user-invocable: true
allowed-tools: "Read Grep Bash"
---

# 統合レビュー（/review）— 公式 /code-review への薄いアダプタ

## 役割（ADR-0027）

機構は公式 `/code-review` に委ね、ccs は **PJ 規範の注入と最終ゲートだけ**を担う。このスキルは機構を再実装しない。

| 層 | 担当 | 実体 |
|---|---|---|
| 決定的検査 | ccs | `review-fitness.sh`（破壊的キーワード・a11y・エラー握りつぶしを LLM の前に落とす。diff 1 回 + awk 1 プロセス） |
| 機構（一般レビュー） | 公式 | `/code-review`（effort 段階・cloud ultra） |
| PJ 規範 | ccs | `REVIEW.md`（HARD照合・ADR整合・破壊的変更・hook教訓・severity・findings 契約） |
| 唯一のロジック | ccs | **min() 総合判定**（BLOCKER が 1 件でも総合ブロック） |

## Step 0: 前提の実在確認（fail-closed・判定より前）

このアダプタは自分が持っていない部品を静かに飛ばせてしまう。`REVIEW.md` が無ければ Step 3-2 の PJ 規範 dimension が、`review-fitness.sh` が無ければ決定的検査が、**エラーを出さずに min() から消える**。残った dimension だけで min() を取れば当然通りやすくなるので、欠落は「甘い判定」ではなく「合格」に化ける。下流 PJ に SKILL.md だけが届き両方欠落していた実例がある（配布は差分であって closure ではない）。

```bash
GATE=.claude/scripts/distribution-gate.sh
if [ ! -f "$GATE" ]; then
  echo "[EVIDENCE_REQUIRED] $GATE が存在しません — 配布完結性を検査できないため /review を続行しません"
  echo "  → /adopt-sidekick-update で取り込むか、tag から復元してください"
  exit 3
fi

bash "$GATE"
GATE_ST=$?
# 代入は必ず 0 を返す。`bash "$GATE"; GATE_ST=$?` で終えると、断片全体の exit が
# 代入の 0 になり、ゲートの非 0 が呼び出し側へ一切伝わらない（散文の「停止する」
# だけでは、この gate が防ごうとしている silent pass がここで再現する）。
# 明示的に非 0 を返して初めて、機械が止められる。
if [ "$GATE_ST" -ne 0 ]; then
  echo "[EVIDENCE_REQUIRED] 配布完結性ゲートが exit $GATE_ST — 総合判定を出さずに停止します"
  exit "$GATE_ST"
fi
```

**`GATE_ST` が 0 以外なら、いかなる総合判定も出さずに停止する。** 分岐は必ず default（`*)`）まで書く:

| exit | 意味 | 動作 |
|---|---|---|
| 0 | 参照先すべて実在 | Step 1 へ進む |
| 3 | companion 欠落（EVIDENCE_REQUIRED） | **停止** |
| 4 | 判定不能（manifest 欠落 / repo 外） | **停止** |
| 5 | 検査器自体が不在 | **停止** |
| 6 | bootstrap 失敗（ref に無い / 空 / chmod 失敗） | **停止** |
| 7 | 検査器が想定外の exit を返した | **停止** |
| **その他（`*)`）** | 未知の状態 | **停止**（想定外は成功ではない） |

停止時に出すのは「欠落一覧 + `/adopt-sidekick-update` の案内」だけ。**この検査を「今回は不要では」で飛ばさない** — 飛ばした結果は無音の合格であり、飛ばしたこと自体が出力に残らない。

### 欠落を承知で部分レビューを続ける場合（ユーザーが明示したときのみ）

分析結果の提示は許容する。**合格判定は許容しない**（観測していない dimension を含む集合に min() は定義できない）:

- **「PR作成可」「承認」「マージ可」「総合 3」「総合 2」「レビュー完了」「問題なし」等、合格・通過を意味する語を一切使わない**
- 最終状態は必ず **`INCOMPLETE / EVIDENCE_REQUIRED`** に固定する
- min() を**算出しない**。欠落した dimension 名を列挙し「未検査であって合格ではない」と明記する
- 出力の見出し行に「配布欠落のため部分レビュー」と書き、承認を求める箇所に置く（末尾の注記では読まれない）

## Step 1: 変更範囲の把握

```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@')
[ -z "$BASE_BRANCH" ] && git rev-parse -q --verify origin/main >/dev/null && BASE_BRANCH=origin/main
[ -z "$BASE_BRANCH" ] && BASE_BRANCH=main   # fresh clone with origin/HEAD unset
git diff "$BASE_BRANCH"...HEAD --name-only
git diff "$BASE_BRANCH"...HEAD --stat
git log "$BASE_BRANCH"...HEAD --oneline
```

> **BASE_BRANCH の判定**: `git symbolic-ref refs/remotes/origin/HEAD` を一次ソースにする。CLAUDE.md の `STG_ENABLED=true` なら上書き: 現在 `feature/*` → `origin/release/stg`、`release/stg` → `origin/main`。`STG_ENABLED=false` は symbolic-ref のまま。

## Step 2: 決定的 fitness 前置ゲート

LLM 観点を回す**前に**機械で落とす。決定的で、LLM 観点を増やさない。

```bash
.claude/skills/review/scripts/review-fitness.sh "$BASE_BRANCH"; FIT_ST=$?
# 0=検出なし / 1=検出あり(WARN 入力) / 2=走査できず(判定不能)。2 を 0 と混同しない。
case "$FIT_ST" in
  0|1) : ;;
  *)   echo "[EVIDENCE_REQUIRED] fitness が走査できませんでした（exit $FIT_ST）— 決定的検査 dimension は未観測です"
       echo "  → BASE_BRANCH ($BASE_BRANCH) が解決するか確認。解消するまで合格判定を出さない"
       exit "$FIT_ST" ;;
esac
# STACK_PACK=nextjs かつ pack 同梱ありで app/lib/components/prisma に触れる時のみ:
PACK=$(grep -E "^STACK_PACK:" CLAUDE.md 2>/dev/null | sed -E 's/^STACK_PACK:[[:space:]]*([a-z]+).*/\1/')
GATE=.claude/stack-packs/nextjs/fitness-functions/run-fitness.js
if [ "$PACK" = "nextjs" ] && [ -f "$GATE" ] && git diff "$BASE_BRANCH"...HEAD --name-only | grep -qE '(^|/)(app|lib|components|prisma)/'; then node "$GATE" .; fi
```

- `review-fitness.sh` の検出は **WARN 入力**（Step 5 の min() に渡す。レビューで最終 severity を確定）。
- **exit 2 は「検出なし」ではなく「検査していない」**。明示 BASE が解決しない・`git diff` が失敗した場合に返る。この状態で Step 5 へ進むと未観測の dimension を合格として数えるので、Step 0 と同じく `INCOMPLETE / EVIDENCE_REQUIRED` で止める。
- `run-fitness.js` の **error（exit 1）は BLOCKER**（Tier-1 違反・HARD 扱い）、warn は WARN。scope 外 / `STACK_PACK=none` は沈黙通過（コスト ゼロ）。
- hook（guard-commit / pre-commit PII / guard-bash）が既に fail のものは無条件 BLOCKER（REVIEW.md §0）。

## Step 3: 公式 /code-review（機構）+ REVIEW.md（規範）

**境界層（ADR-0027 決定 3・外部依存は失敗する前提）**:

```bash
source .claude/hooks/hook-helpers.sh
ccs_official_gate code-review-ultra   # ultra を使う場合のみ。CLI が古ければ WARN → 非 ultra に落とす
```

1. `/code-review` を変更規模に応じた effort で実行する（doc/小変更=low〜medium、セキュリティ/大規模/DB=high、重要 PR=ultra）。公式は **REVIEW.md を最優先で観点に注入する**。
2. **二重適用（fallback を兼ねる）**: 注入に依存しきらず、**このスキルでも `REVIEW.md` を Read し §1 の PJ 規範（HARD照合・ADR整合・破壊的変更・hook教訓）を diff に適用する**。これにより (a) 注入が効かない公式バージョン (b) `/code-review` 自体が不在の古い CLI でも、PJ 規範と min() が生きる。
3. `/code-review` が**不在**（コマンドなし）なら、`ccs_official_gate` の WARN を surface した上で、REVIEW.md 準拠の手動レビューに切り替える（silent 破綻禁止）。

## Step 4: /verify 提案（R9）

diff が**ランタイム表面**（`app/` `api/` `src/` UI コンポーネント・hooks 実体）に触れる → 静的レビュー後に公式 `/verify` を提案する。docs / rules / テストのみ → 提案しない。

## Step 5: min() 総合判定（唯一のロジック）

`references/scoring-guide.md` を Read し、**全 finding（fitness + /code-review + REVIEW.md PJ 規範）を severity 別に集計**する。

```
各観点/検出源のスコア: BLOCKER あり=1 / WARN のみ=2 / INFO のみ or 指摘なし=3
総合 = min(全スコア) = 存在する最悪 severity
```

**平均・多数決・「全体としては良いので」による格上げは禁止。BLOCKER が 1 件でもあれば総合 1。**

### 出力フォーマット

```
=== 統合レビュー結果 ===

[前提]        配布完結: OK / 欠落 N 件（欠落時は最終判定行に「dimension 欠落」を明記）
[fitness]     決定的検出: なし / N 件（WARN 入力）
[code-review] 公式レビュー: 指摘なし / BLOCKER n / WARN n / INFO n
[PJ規範]      REVIEW.md §1: 整合 / HARD照合 or ADR整合 or 破壊的変更に指摘
[Arch]        アーキ OK / 逸脱あり（fitness）/ 対象外（STACK_PACK=none・scope 外）

最終判定: PR作成可（総合3/2）/ ブロッカーあり（総合1・PR不可）
        / INCOMPLETE / EVIDENCE_REQUIRED（配布欠落 — min() を出さず合格判定もしない）

指摘サマリ（file:line + 欠陥1文 + 失敗シナリオ。REVIEW.md §4 契約）:
  [BLOCKER] ...
  [WARN]    ...
  [INFO]    ...
```

**事実忠実性（CLAUDE.md ゲート 2）**: 仕様・API 名・挙動を根拠にする指摘は、当該セッションで一次ソースを見たものだけ断定する。見ていなければ「推測」と明記（plausible-but-wrong 1 件は見逃し 1 件より信頼を損なう）。

## 公式スキルとの使い分け

`/code-review`・`/simplify`・`/verify`・`/security-review` の役割分担は `references/official-skills.md` を参照。

## Gotchas

- **fitness を重くしない** — `review-fitness.sh` / `run-fitness.js` は決定的スクリプト。LLM 観点を増やさない。scope 外・`STACK_PACK=none` では沈黙通過（ADR-0022 軽さドクトリン）。重いと回すのが億劫になりサイクルが死ぬ。
- **min() を格上げしない** — 平均・多数決・情状酌量で総合を上げない。BLOCKER 1 件＝総合 1。これが診断の最重要発見（rubric 既在なのに未配線だと標準モデルは甘い判定に流れる）。
- **欠落した部品を沈黙で飛ばさない（Step 0）** — `REVIEW.md` / `review-fitness.sh` が無い PJ で「総合3・PR作成可」を出すのは、判定が甘いのではなく **観測していない dimension を合格に数えている**。gate が 0 を返した時だけ判定してよく、それ以外（default 分岐を含む）は `INCOMPLETE / EVIDENCE_REQUIRED` で止める。
- **fitness の exit 2 は「検出なし」ではない** — `review-fitness.sh` は走査できなかったとき exit 2 を返す（明示 BASE が解決しない / `git diff` 失敗）。0 と混同すると、検査していない diff を「決定的検出なし」として min() に入れることになる。
- **外部依存は失敗する前提** — `/code-review` の REVIEW.md 注入に依存しきらず、このスキルでも REVIEW.md を Read して二重適用する（Step 3-2）。注入が no-op / コマンド不在でも PJ 規範を落とさない。
- **旧 review-* 5 スキルは撤去済み**（`/review` に統合。移行: `docs/migrations/review-6to1-adapter.md`） — 観点別の深掘りは公式 `/code-review` の effort と `/security-review` に委譲する。
