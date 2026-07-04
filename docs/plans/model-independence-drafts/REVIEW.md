# REVIEW.md 原案 — 公式 /code-review への PJ 観点注入（WS2 で配置）

> **これは Phase 0 原案**。WS2 実装時にリポジトリルートの `REVIEW.md` として配置し、/setup が下流 PJ 向けに Project Configuration の値で生成する（`{{...}}` はテンプレート変数）。
> 公式 /code-review は REVIEW.md を最優先で system prompt に注入する。ここには「公式が知り得ない PJ 規範」だけを書く（一般的なコードレビュー観点は公式に委ねる）。

---

## 0. 決定的検査を先に信頼する

以下は機械検査（スクリプト/hook）が担当する。レビューで再導出せず、結果を前提にする:

- コミット規約（背景/対応/影響）→ guard-commit-message.sh が強制済み
- PII 混入 → githooks/pre-commit が強制済み
- 破壊的マイグレーションキーワード（DROP / ALTER TYPE / RENAME / NOT NULL 追加）→ fitness スクリプトの検出結果を参照
- 保護ブランチ・.env・PRD DB → hooks が物理ブロック済み

機械検査が fail を出している場合、その項目は無条件で BLOCKER とする（レビューで上書きしない）。

## 1. PJ 規範の観点（このリポ固有・公式レビューへの追加観点）

### 1a. HARD ルール照合

diff が以下に触れる場合、該当 HARD ルール（CLAUDE.md §2）を引用して整合を判定する:

- DB スキーマ / マイグレーション → H3, H4, H14（並行禁止）
- .env / 接続文字列 → H5
- git 操作を含むスクリプト / hook → H7, H8, H9
- hooks / guard スクリプト自体の変更 → **ガードの弱体化がないか**（迂回可能化・パターン緩和・fail-open の範囲拡大）。弱体化は常に BLOCKER

### 1b. ADR / 仕様整合

1. 変更パスに言及する ADR を機械抽出した一覧（fitness スクリプト出力）を受け取る
2. 各 ADR の「決定」と diff が矛盾しないかを判定する。矛盾があれば「ADR 改訂 or 実装修正」の二択を提示する（黙って通さない）

### 1c. 破壊的変更（Expand-Contract）

検出済みの破壊的キーワードがある場合: 2 段階リリース（先に追加系→後に削除系）になっているか。backfill スクリプトに `--dry-run` があるか（rules/deploy-strategy.md）。

### 1d. hook / シェルスクリプトの PJ 教訓

- `echo "$VAR" | jq` は禁止（`printf '%s\n' "$VAR" |` を使う。POSIX 未定義のバックスラッシュ展開でガード全滅の実績あり — CLAUDE.md §3）
- jq には `2>/dev/null` + grep フォールバック
- Stop hook は stdout 出力で無限ループする。`type: "prompt"` 禁止・command は stdout 空

### 1e. {{STACK_PACK 有効時のみ}} golden path 準拠

stack pack の ARCHITECTURE.md（Tier-1 STRUCTURAL / Tier-2 HYGIENE)との整合。Tier-1 違反は BLOCKER。

## 2. severity の定義（裁量で変えない）

| severity | 条件（1 つでも YES） |
|---|---|
| **BLOCKER** | データ喪失・本番影響の可能性 / ガード・安全機構の弱体化 / HARD ルール違反 / ADR 矛盾の未解決 / 機械検査 fail |
| **WARN** | 教訓（§1d）違反 / 破壊的変更の手順不備 / テスト欠落（変更されたランタイム表面に対応テストなし） |
| **INFO** | 改善提案・スタイル・将来リスク |

## 3. 総合判定（min() ルール — references/scoring-guide.md と同一）

各観点のスコア: BLOCKER あり=1 / WARN のみ=2 / INFO のみ or 指摘なし=3。

**総合 = min(全観点スコア)**。3=PR 作成可 / 2=修正推奨（ユーザー判断で PR 可）/ 1=ブロッカーあり（PR 不可）。

平均・多数決・「全体としては良いので」による格上げは禁止。BLOCKER が 1 件でもあれば総合 1。

## 4. findings の出力契約

各 finding は必ず: `file:line` + 欠陥の 1 文 + **具体的な失敗シナリオ**（この入力/状態 → この誤動作）。

- NG 例: 「エラーハンドリングが不十分」（場所・シナリオなし）
- OK 例: 「`sync.sh:42` — jq パース失敗時に空文字が返り、以降の全ガード判定が allow に倒れる。Windows パスを含む stdin で再現」

**事実忠実性**: 仕様・API 名・挙動を根拠にする場合、当該セッションで一次ソース（コード・実行結果・公式ドキュメント）を見たものだけ断定してよい。見ていなければ「推測」と明記する。plausible-but-wrong な指摘 1 件は、見逃し 1 件より信頼を損なう。
