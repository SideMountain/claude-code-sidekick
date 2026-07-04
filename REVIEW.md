# REVIEW.md — 公式 /code-review への PJ 規範注入

> 公式 `/code-review` はこのファイルを最優先でレビュー観点として読み込む。ここには**公式が知り得ない PJ 規範**だけを書く。一般的なコードレビュー観点（correctness バグ・簡潔化・効率）は公式に委ねる。
> ccs の `/review` アダプタもこのファイルを Read し、決定的検査（fitness）と統合して min() 総合判定を出す（公式への注入が効かないバージョンでも規範が生きるよう、二重に適用する）。
> 下流 PJ 向けには `/setup` が Project Configuration の値でこのファイルを配置・調整する。

---

## 0. 決定的検査を先に信頼する

以下は機械検査（hook / スクリプト）が担当する。レビューで再導出せず、結果を前提にする:

- コミット規約（背景/対応/影響）→ `guard-commit-message.sh` が強制済み
- PII 混入 → `.claude/githooks/pre-commit` が強制済み
- 保護ブランチ・.env・PRD DB 操作 → `guard-bash.sh` / `guard-db-operation.sh` が物理ブロック済み
- 破壊的マイグレーション・a11y 欠落・空 catch → `.claude/skills/review/scripts/review-fitness.sh` の検出結果を参照

**hook が fail を出している項目は無条件で BLOCKER**（レビューで上書きしない）。fitness の検出は WARN 入力（レビューが §2 の定義で最終 severity を確定する）。

> **PII の守備範囲に注意**: pre-commit（コミット時強制）は**公開ファイルへの PII 混入**のみを走査する。**ランタイム PII**（ログ・API レスポンス・エラーメッセージへの流出）はアプリコードを走査しないため検知されない → §1i でレビューする。「PII は強制済み」で油断しない。

## 1. PJ 規範の観点（このリポ固有・公式レビューへの追加観点）

### 1a. HARD ルール照合（CLAUDE.md §2）

diff が触れる領域ごとに、該当 HARD ルールを引用して整合を判定する:

- DB スキーマ / マイグレーション → H3, H4, H14（並行禁止）
- .env / 接続文字列 → H5
- git 操作を含むスクリプト / hook → H7, H8, H9
- **hooks / guard スクリプト自体の変更 → ガードの弱体化がないか**（迂回可能化・パターン緩和・fail-open の範囲拡大・AUTO_MODE の既定変更）。弱体化は常に BLOCKER

### 1b. ADR / 仕様整合

1. 変更パスに関連する ADR（`docs/decisions/`）を特定する
2. 各 ADR の「決定」と diff が矛盾しないか判定する。矛盾があれば「ADR 改訂 or 実装修正」の二択を提示する（黙って通さない）
3. 仕様書がある場合（`NOTION_ENABLED=true` は Notion 設計書）、受入条件を先に箇条書きにし、各条件の実装該当行を対応付ける

### 1c. 破壊的変更（DB + API 契約・Expand-Contract）

- **DB**: fitness が破壊的キーワード（DROP / ALTER TYPE / RENAME）を検出した場合、2 段階リリース（先に追加系 → 後に削除系）か。backfill に `--dry-run` があるか（rules/deploy-strategy.md）。NOT NULL 追加は default なし or 既存行の埋めなしなら破壊的。
- **API 契約（非 DDL・fitness では拾えない）**: レスポンス型/フィールドの削除・rename、必須リクエストパラメータの追加、エラー形式の変更は既存クライアントを壊す。移行期間（両対応 → 切替）があるか。

### 1d. hook / シェルスクリプトの PJ 教訓（CLAUDE.md §3 Lessons）

- `echo "$VAR" | jq` 禁止（`printf '%s\n' "$VAR" |` を使う。POSIX 未定義のバックスラッシュ展開でガード全滅の実績）
- jq には `2>/dev/null` + grep フォールバック
- Stop hook は stdout 出力で無限ループする。`type: "prompt"` 禁止・command は stdout を空にする
- PreToolUse guard は allow/deny を JSON で返す（hook-helpers.sh の `deny` / `allow_with_context`）。fail-open 方向の挙動変更は §1a のガード弱体化に該当

### 1e. design-system 準拠（PJ に design-system がある場合のみ）

UI 変更が design-system の token（色・spacing・typography）を使っているか。hex 直書き・任意 px 値・非トークン色は WARN。alt 欠落・label なし input は fitness が grep するのでその結果を参照する。

### 1f. STACK_PACK golden path（`STACK_PACK=nextjs` の PJ のみ・ccs 本体は none で非該当）

stack pack の `ARCHITECTURE.md`（Tier-1 STRUCTURAL / Tier-2 HYGIENE）との整合。Tier-1 違反は BLOCKER。決定的検査は `run-fitness.js` の結果を参照する。

> **以下 §1g–§1k は「汎用コードレビューが構造的に苦手 / スコープ外」な高価値観点**。公式 `/code-review` は diff の correctness に強いが、並行性推論・diff 外への波及・実データとの突合・実行時の副作用は落としやすい。REVIEW.md がこれらを明示することで標準モデルでも観点が抜けない（過剰蒸留の防止）。

### 1g. 並行性・冪等性（grep で判定不能・レビュー必須）

新規/変更した書き込み経路に競合はないか: 読み取り → 判定 → 書き込みの間に別リクエストが割り込む（read-check-write）/ Webhook・リトライの再送で二重処理 / 冪等キーの欠如。並行実行は diff レビューで最も見落とされる。

### 1h. 外部依存の耐障害性（brain「外部依存は失敗する前提」）

新規の外部呼び出し（fetch / API / SDK / 外部 DB）ごとに: timeout・retry・graceful degradation があるか。失敗が主フローから隔離され監視に通知されるか（catch で握りつぶさず reporter を呼ぶ — fitness は**空** catch のみ機械検出。reporter 欠落・多行 catch は要レビュー）。

### 1i. ランタイム PII（pre-commit の対象外・§0 参照）

アプリコードが PII を実行時に露出しないか: ログへの個人情報出力 / 過剰な API レスポンス（内部 ID・ハッシュ・他人のデータ）/ エラーメッセージへの DB 内部露出 / URL パラメータへの PII。

### 1j. モック忠実性（「テスト green・本番壊れる」の防止）

手書きモック/スタブの戻り値の型・構造が、実際の DB/API の返り値と一致するか。乖離するとテストは通るが本番で undefined 参照・型不整合になる。スキーマ変更を含む diff では必ず突合する。

### 1k. 水平展開（diff 外への波及）

diff が修正した欠陥パターン（認可漏れ・入力検証漏れ等）を抽出し、**変更されていない同種箇所**にも同じ欠陥がないか grep で網羅する。公式 `/code-review` は diff スコープに閉じるため、この横断は REVIEW.md 側の責務。

## 2. severity の定義（裁量で変えない）

| severity | 条件（1 つでも YES） |
|---|---|
| **BLOCKER** | データ喪失・本番影響の可能性 / ガード・安全機構の弱体化 / HARD ルール違反 / ADR 矛盾の未解決 / hook 機械検査 fail |
| **WARN** | PJ 教訓（§1d）違反 / 破壊的変更の手順不備 / テスト欠落（変更されたランタイム表面に対応テストなし）/ a11y 欠落 / 非トークン色 |
| **INFO** | 改善提案・スタイル・将来リスク |

**「弱体化」の較正**: BLOCKER の弱体化とは**既存防御の後退**（従来 deny／検知していた入力が通るようになる・fail-open 化・フォールバック削除）。**新設ガード自体の不備**（迂回残り・設定ミスで silent no-op）は、防御が後退していないため弱体化ではなく WARN（上位レイヤの人間承認等が残る場合は特に）。新設か後退かを diff の before 側で必ず確認してから severity を確定する。

## 3. 総合判定（min() ルール）

各観点のスコア: **BLOCKER あり=1 / WARN のみ=2 / INFO のみ or 指摘なし=3**。

**総合 = min(全観点スコア)**。3 = PR 作成可 / 2 = 修正推奨（ユーザー判断で PR 可）/ 1 = ブロッカーあり（PR 不可）。

平均・多数決・「全体としては良いので」による格上げは禁止。**BLOCKER が 1 件でもあれば総合 1**。
（`/review` アダプタは `.claude/skills/review/references/scoring-guide.md` の同一ルールで機械集計する。両者は同じ min() を指す。）

## 4. findings の出力契約

各 finding は必ず: `file:line` + 欠陥の 1 文 + **具体的な失敗シナリオ**（この入力 / 状態 → この誤動作）。

- NG 例: 「エラーハンドリングが不十分」（場所・シナリオなし）
- OK 例: 「`sync.sh:42` — jq パース失敗時に空文字が返り、以降の全ガード判定が allow に倒れる。Windows パスを含む stdin で再現」

**事実忠実性（CLAUDE.md ゲート 2）**: 仕様・API 名・挙動を根拠にする指摘は、当該セッションで一次ソース（コード・実行結果・公式ドキュメント）を見たものだけ断定する。見ていなければ「推測」と明記する。plausible-but-wrong な指摘 1 件は、見逃し 1 件より信頼を損なう。
