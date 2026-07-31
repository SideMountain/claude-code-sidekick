---
name: auto-implement
description: "全自動実装の指揮者。設計確定済みの作業を、公式部品（plan mode・/goal・/verify・/code-review）を brain + HARD 制約下で組み合わせて実装→検証→レビュー→PR まで無人で回す。"
user-invocable: true
allowed-tools: "Read Write Edit Grep Glob Bash Agent Skill"
---

# /auto-implement — 全自動実装の指揮者

## 役割（ADR-0027・指揮者化）

機構（分解・完了条件評価・動作実証・レビュー）は**公式部品に委ね**、ccs は無人実行の**安全の要**だけを担う。このスキルは機構を再実装しない。

| 層 | 担当 | 実体 |
|---|---|---|
| 入口ゲート | ccs | R1 rubric（Phase 0・1つでも NG→停止） |
| 分解 | 公式 | plan mode |
| 完了条件宣言 | 公式 | `/goal`（完了条件を設定し複数ターン自動実行・軽量評価器） |
| 動作実証 | 公式 | `/verify`（R9: ランタイム表面に触れる時） |
| レビュー | ccs アダプタ→公式 | `/review`（fitness→`/code-review`+REVIEW.md→min()） |
| 難所裁定 | ccs | R2 閉集合 + R3 敵対検証 |
| 状態の外部化 | ccs | progress ledger（ADR-0024） |
| budget 連動 | ccs | THROTTLE 時は fan-out 幅のみ縮退（正しさは削らない） |

## 前提条件

- **設計・仕様が確定済み**（Phase 0 の R1 で機械判定する。「だいたい決まってる」は未確定と同じ）。
- **全自律には `SIDEKICK_AUTO=true` 起動が必須**（ADR-0026・既定 `false`）。未指定だと push/PR で確認待ちになる（H7/H8）。無人起動: `SIDEKICK_AUTO=true claude --dangerouslySkipPermissions -p "/auto-implement #123"`。

---

## Phase 0: 入口ゲート（R1 rubric）

入力（`#123` / 作業指示テキスト / `BACKLOG.md`）を解析し本文を取得。**全問 YES で開始。1 つでも NO → 停止し、NO の項目を列挙して人間に差し戻す。**

| # | 質問 | 判定方法 |
|---|---|---|
| 1 | 実装対象の ADR または Issue 本文が存在するか | 機械（`gh issue view` / `ls docs/decisions`） |
| 2 | 本文に未決定マーカーが残っていないか | 機械 grep + モデル確認 |
| 3 | 完了条件が観測可能な形か（実行できるコマンド／通るテスト／確認できる画面のいずれかに言及） | rubric |
| 4 | 完了条件に曖昧語が含まれていないか | 機械 grep |
| 5 | 影響範囲（ファイル／ディレクトリ）が本文に列挙されているか | rubric |
| 6 | DB マイグレーション要否が判定済みか | 機械（本文言及 or schema/migrations パス変更） |
| 7 | 他の Active Work と影響範囲が重複していないか（重複時 H14 照合） | 機械（パス積集合）+ rubric |

```bash
BODY="$1"   # Phase 0 で取得した Issue/ADR 本文
printf '%s' "$BODY" | grep -nE 'A案|B案|どちらでも|後で決める|要検討|TBD|未定' && echo "Q2 NG: 未決定マーカー"
printf '%s' "$BODY" | grep -nE 'いい感じ|だいたい|適宜|なるはや|よしなに|お任せ' && echo "Q4 NG: 曖昧語"
printf '%s' "$BODY" | grep -nqE 'schema|migrations?|prisma/migrat' && echo "Q6: migration 言及 → 要否を明示判定（要なら H14 で停止）"
```

- Q6 で DB マイグレーションが必要 → **ここで停止**（H14: 自動実行禁止）。
- Q7 でパス積集合が非空、かつ一方がマイグレーション → 停止（H14 並行禁止）。それ以外の同一ファイル競合は「迷ったら順次」。

## Phase 1: 環境準備（H12/H13/H1）

```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
BRANCH_NAME="feature/auto-$(date +%Y%m%d-%H%M%S)"
git worktree add "../$(basename $(pwd))-auto" -b "$BRANCH_NAME" "origin/$BASE_BRANCH"
```

1. Worktree 作成（H12）→ **MEMORY.md Active Work に記録（H13・この順序）**。
2. `.env` コピー + 接続先確認（H1）+ 依存インストール（ランタイム不要なら軽量 worktree でスキップ）。
3. **progress ledger 初期化**（後述）。

## Phase 2: 計画 + 実装（公式部品）

1. **plan mode で分解** — 作業を検証可能な最小単位に割る。1 単位 = テスト緑で都度証明できる粒度。
2. **`/goal` で完了条件を宣言** — Phase 0 の完了条件（コマンド／テスト／画面）を `/goal` に渡し、複数ターン自動実行させる。**駆動主体は本スキルの指揮ループ**。/goal は完了条件の宣言と達成確認の補助で、内側の実装リトライ（最大3回）は下記 Agent 隔離実行が担う。**/goal 評価器の判定は補助入力**であって、完了の主判定は機械検証（`TEST/TYPECHECK/BUILD` green・Phase 4）。
3. **実装は Agent ツールで隔離実行**（CLAUDE.md / brain 自動ロード）。thinking.md Step 1（現状調査）→ 実装 → スコープテスト → 失敗は修正ループ（最大3回）→ コミット（背景/対応/影響・H15）。
   - **R4-impl（編集直前ゲート・ADR-0028 決定4）**: 変更対象の関数・シンボル・設定キーを当該セッションで Read していなければ、編集前に必ず Read する。新規に呼ぶ外部 API・コマンドは一次ソース（公式ドキュメント・`--help` 実行）を確認してから使う。記憶・推測で API 名・引数・挙動を書かない。
4. **`/verify` で動作実証（R9）** — diff がランタイム表面（`app/` `api/` `src/` UI・hooks 実体）に触れる → `/verify` で end-to-end 実証。docs / rules / テストのみ → `/verify` は省略するが、**完了判定に機械確認を最低 1 つ必須**（リンク切れ grep・整形チェック・当該スクリプトの実行のいずれか）。評価器のみでの完了判定は禁止。

> 公式部品は**存在チェック**してから使う（ADR-0027 決定3・外部依存は失敗する前提）: `source .claude/hooks/hook-helpers.sh; ccs_official_gate goal; ccs_official_gate verify`。不在なら WARN を surface し、Phase 2 の Agent ループ（テスト緑ゲート）に fallback する（silent 破綻禁止）。

## Phase 3: レビュー裁定（難所 = R2 最終 judge）

Agent 完了後、**メインコンテキストに戻って** `/review` を実行する（Agent 内から呼ぶと入れ子で深さ制限に抵触）。

1. `/review` アダプタが fitness → `/code-review`+REVIEW.md → **min() 総合判定**を返す。
2. **`/review` の verdict をそのまま採用する（再判断しない・診断 #3）。** ccs 側で「全体としては良いので格上げ」しない。
3. **矛盾 findings**（観点間・仕様と実装・ADR と diff の食い違い）は R2 難所 = **単発判断を禁止**。R3 敵対検証を多視点 judge へ fan-out して裁定する（下記）。
4. min()=1（BLOCKER）→ **ledger に記録して停止**（ユーザー判断待ち）。min()≧2 は WARN を修正 → 再 `/review`（最大3回）。

## Phase 4: 全テスト + PR（ADR-0026）

```bash
$TEST_COMMAND && $TYPECHECK_COMMAND && $BUILD_COMMAND   # PR 作成前ゲート
```

| モード | git push / gh pr create |
|---|---|
| 対話（`SIDEKICK_AUTO` 未設定=既定 `false`） | H7/H8 どおり**確認待ち**（正常動作） |
| 無人（`SIDEKICK_AUTO=true` + `--dangerouslySkipPermissions`） | 自動実行 |

保護ブランチ push・PRD DB 等のハードブロックは AUTO_MODE 非依存で常に deny（ADR-0026）。

## Phase 5: 知識蓄積 + ledger（/close-chat 相当）

無人でも知識をロストしない。

- **5a 実行サマリ** → ledger + MEMORY.md Active Work（ブランチ / PR / 結果 / 停止時は理由 + 再開情報）。
- **5b 知識還流** — 記録トリガ: /review で WARN 以上 / テスト失敗→修正ループ発生 / 新パターン採用。分類は `.claude/docs/knowledge-reflux.md` の**還流 3 分類（R7）**に従う（`[OSS 還流候補]` / `[個人 brain 昇格]` / `[PJ 固有]`）→ MEMORY.md 知識還流フラグ。該当なしは記録しない（過剰蓄積防止）。
- **5c バックログ** — INFO 指摘 / 変更ファイル外 / 再現手順が書ける、の YES で `BACKLOG.md` へ。
- **5d 外部DB同期**（Layer 2・任意）。
- **5e 統合レポート** — フォーマットと few-shot 3 例は `references/report-examples.md` を Read して生成。ゴール: 朝5秒で状況把握・PR を開かず次アクションを決められる。

---

## budget-gate 連動（ADR-0024）

Stop hook（`budget-cycle-halt.sh`）の systemMessage で状態を受け取り、指揮者が幅を制御する。**縮退するのは幅であって正しさではない**（決定5・聖域）。

| 状態 | 指揮者の振る舞い |
|---|---|
| NORMAL | 通常。 |
| **THROTTLE**（60–85%） | **fan-out 幅のみ縮退**（並列 worktree 本数を減らす・R3 敵対検証の**票数のみ**減らす・出力簡約）。難所の敵対検証は**発火自体は維持**。縮退した事実（何を何票→何票にしたか）を **ledger に明示**（silent drop 禁止・§7）。 |
| **PAUSE**（>85%） | 次の Stop 境界で ledger + commit を残して休止。実行中の単一ツールは殺さない。`resets_at` まで新規着手しない。 |

## 難所判定（R2）— 単一ソース + 機械 force-flag

**閉集合 5 項目・エスカレーション ladder（L1–L4）・R3 敵対検証の定型は `.claude/rules/context-economy.md` §8 が単一ソース**（ここには再掲しない）。本スキルでの発火点:

1. **機械 force-flag を前置**（ADR-0028 決定3）: `bash .claude/scripts/detect-hard-spot.sh "origin/$BASE_BRANCH"` を実行し、**HARD_SPOT 出力が 1 行でもあれば難所として扱う**。モデルの自己判定で force-flag を**否定するのは禁止**（追加する方向のみ可）。
2. **Phase 2**: 実装中の設計判断・root-cause は難所 → §8 ladder（L2 多視点 3 票 / L3 実行 arbiter）を発火。
3. **Phase 3**: レビューの矛盾裁定は難所。**最終 judge（マージ可否 / 無人続行可否）は L4**（多エージェント裁定 + min()）。

多視点 judge へ fan-out する時は Agent を独立起動し別レンズ（correctness / security / 再現性）を割り当てる。THROTTLE 時は票数のみ縮退し ledger に記録（L1 の 1 本・L3 の実行 arbiter は縮退対象外・§8）。

## fan-out 発火条件（R8 trivial-gating）

**全て YES なら single-thread**（fan-out・多段検証を発火しない）:

1. 変更ファイル数 ≤ 3　2. diff 合計 ≤ 80 行　3. 全パスが `docs/**` / `*.md` / `.claude/rules/**`（ランタイム非接触）　4. R2 難所の閉集合に非該当

1 つでも NO → 通常ゲート（難所判定 → 必要なら fan-out）。

## progress ledger（ADR-0024 決定1）

自律ループの記憶を会話履歴でなく **disk の ledger** に置き、サイクル境界で context をリセットする（再開は ledger の read だけ）。

- **配置**: auto-memory ディレクトリの `ledger_auto-implement_<branch>.md`（git 非追跡・worktree 削除後も残る・サイクル/会話跨ぎで永続）。索引 1 行を MEMORY.md Active Work に置く。
- **各サイクル境界で追記**: 決定 + why / 残タスク / 次の一手 / 検証結果 / THROTTLE 縮退記録 / 停止理由。
- PAUSE の wrap-up turn は必ずこの ledger へ書き、commit してから停止する（budget-cycle-halt が促す）。

## 並列実行（/batch）

複数 Issue は `/batch`（公式・5–30 worktree を自動分割）で並列化。発火前に R8 と競合判定:

- 各 Issue の影響範囲を本文からパス抽出 → **積集合が非空**なら順次（安全側）。マイグレーション同士は H14 で必ず順次。
- 各 Agent はレポートを返し、**メインが1回だけ** MEMORY.md / ledger に書き込む（並列書き込みコンフリクト回避）。
- THROTTLE 時は並列本数を縮退（§budget-gate 連動）。

## 停止条件

| 条件 | 対応 |
|---|---|
| R1 入口ゲート NG | NO 項目を列挙して差し戻し（Phase 0） |
| DB マイグレーション必要 | H14: ユーザー確認待ち |
| テストが3回連続失敗 | ledger 記録 → 停止 |
| /review が BLOCKER（min()=1） | ledger 記録 → 停止 |
| ファイル競合（並列時） | 順次実行に切替 |
| budget PAUSE（>85%） | ledger + commit → reset まで休止 |

「停止する」は正常動作 — ブラックリスト方式（ADR-0002）が正しく機能している証拠。

## Return Contract

**返すもの**: 実装サマリ（変更ファイル + 行数 + アプローチ）/ 検証結果（テスト・型・ビルド・/verify）/ レビュー結果（min() + 修正ループ回数）/ 難所裁定の verdict / budget 縮退の有無 / 知識還流フラグ / バックログ / 停止時は Phase + 理由 + 再開方法。
**返さないもの**: 実装コード全文（PR diff）/ テスト全ログ（CI）/ レビュー全チェック項目（指摘のみ）。

## Gotchas

- **設計未確定での実行** — 最も危険。R1 の機械 grep（未決定マーカー・曖昧語）を人力の目視に置き換えない。1 つでも NG なら Phase 0 で停止。
- **min() を格上げしない** — `/review` の verdict をそのまま採用する。BLOCKER 1 件＝総合 1。無人だと甘い裁定に流れやすいので難所は R3 で敵対検証する。
- **THROTTLE で正しさを削らない** — 削るのは幅（並列本数・票数・冗長出力）だけ。難所の敵対検証は発火を維持し、縮退は ledger に明示（silent drop 禁止）。
- **公式部品は失敗する前提** — `/goal` `/verify` `/code-review` は `ccs_official_gate` で存在チェックし、不在なら WARN + fallback（テスト緑ゲート / REVIEW.md 手動レビュー）。
- **並列実行時の MEMORY.md/ledger 競合** — 各 Agent はレポートを返し、メインが1回だけ書き込む。
