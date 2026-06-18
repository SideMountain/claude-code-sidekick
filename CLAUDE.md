# CLAUDE.md - AI伴走開発 ベーステンプレート

全プロジェクトに共通するルール・方針・制約を定義する。
領域特化ルール（Git戦略・DB・デプロイ・命名規則等）は `.claude/rules/` に配置。

---

## 0. Project Configuration

各セクションのルールはこの設定値に応じて有効/無効が切り替わる。

```yaml
PROJECT_NAME: ""              # プロジェクト名
STG_ENABLED: false            # true: feature→stg→main の2段階リリース
                              # false: feature→main の直接リリース
PROTECTED_BRANCHES:           # 保護ブランチ名（直接コミット・push禁止）
  - main
  # - release/stg            # STG_ENABLED=true の場合に追加
ORM_TYPE: none                # prisma | drizzle | none
LANGUAGE: typescript          # typescript | python | gas
STACK_PACK: none              # none | nextjs : opt-in stack pack（規定アーキ golden path + system-map 可視化）
                              # nextjs: .claude/stack-packs/nextjs/ARCHITECTURE.md の規約に従う（ADR-0021）。none なら無視（無コスト）
TEST_COMMAND: ""              # 例: "npx vitest run", "pytest", ""
TYPECHECK_COMMAND: ""         # 例: "npx tsc --noEmit", "", ""
BUILD_COMMAND: ""             # 例: "npm run build", "", ""
LINT_COMMAND: ""              # 例: "npm run lint", "", ""
NOTION_ENABLED: false         # true: Notion MCP連携有効（Tasks DB 双方向同期）
NOTION_JUDGMENT_SYNC: false   # true: /close-chat 実行時にNotion判断ログDBへ同期
NOTION_JUDGMENT_DB_URL: ""    # 同期先 Notion 判断ログDB の URL（NOTION_JUDGMENT_SYNC=true の場合必須）
PACKAGE_MANAGER: npm          # npm | pnpm | yarn | pip
STG_DB_PATTERN: ""            # STG DB識別パターン（例: "ep-bitter-salad"）
PRD_DB_PATTERN: ""            # PRD DB識別パターン（例: "ep-weathered-mode"）
SIDEKICK_VERSION: ""          # 取り込み済み sidekick バージョン（例: "0.4.1"）
                              # 空 or 未設定なら sidekick 本体として扱う（バージョンチェック対象外）
```

### Stack Pack（opt-in・ADR-0021）

`STACK_PACK: nextjs` の場合、この PJ は **Next.js stack pack の規定アーキ（golden path）に従う**。実装・レビュー時は `.claude/stack-packs/nextjs/ARCHITECTURE.md`（Tier-1 STRUCTURAL / Tier-2 HYGIENE）を実装規約として読み、`system-map` スキルでコードベースを可視化できる。`none`（既定）の場合はこのレイヤー全体を無視してよい（**非 Next PJ は無コスト**）。

stack pack は ccs core の上に載る **opt-in な上物**であって core ではない（core = hooks / brain / 北極星 / skills は stack 非依存）。有効化は `/setup` で対話的に行う。

---

## 1. オーナーの判断軸

判断基盤は **brain (2 層構造)** に定義する。

| 層 | 配置 | スコープ | ロード対象 |
|---|---|---|---|
| 個人 brain | `~/.claude/brain/thinking.md` | 個人（複数 PJ 横断）。利用者が育てる | ✅ |
| PJ 固有 brain | `.claude/brain/thinking.md` | この PJ 固有 | ✅ |

PJ 固有 brain が `@~/.claude/brain/thinking.md` で個人 brain を 1 段 `@import` する。個人 brain 不在時は silent ignore され、PJ brain だけがロードされる（フェイルセーフ）。

OSS 配布物の `brain/thinking.md` は個人 brain の初期テンプレート素材としてリポに含まれるが、ロード対象ではない（`/setup` で個人 brain を初期化する際の素材）。詳細は ADR-0016 を参照。

@.claude/brain/thinking.md

---

## 2. Claude 運用ルール

### ルールグレード

| グレード | 意味 | Claudeの動作 |
|----------|------|-------------|
| **HARD** | 例外なし。効率や文脈を理由に省略不可 | 機械的に実行。**判断しない** |
| **SOFT** | 原則従う。文脈で判断してよい | 判断した場合は根拠を明示 |
| **GUIDE** | 推奨。従わなくても報告不要 | 意識するが厳密に従わなくてよい |

**HARD ルールに対して「今回は不要では？」「さっき確認した」等の判断を適用しない。** 判断するから間違える。

---

### HARD ルール一覧

#### 本番データ保護

- **H1**: DB操作前に `grep "^DATABASE_URL" .env` を毎回実行（「さっき確認した」は省略理由にならない）
- **H2**: PRDデータパッチは dry-run → 件数確認 → 承認 → 実行
- **H6**: PRD DB書き込み: 手順・影響行数・ロールバック提示 → 明示的承認

#### .env 保護

- **H5**: `.env` の `DATABASE_URL` 書き換え禁止（PRD操作はコマンド単位で `DATABASE_URL=` を渡す）
  - ※ `STG_DB_PATTERN` / `PRD_DB_PATTERN` が設定されている場合のみ有効

#### 不可逆Git操作

- **H7**: git push → 必ずユーザー確認
- **H8**: PR作成・マージ・クローズ → 必ずユーザー確認
- **H9**: `PROTECTED_BRANCHES` に直接コミット禁止

#### STG_ENABLED=true の場合のみ有効

- **H10**: feature → main のPR禁止（feature → stg → main の2段階）
- **H11**: main ↔ stg の同期PR禁止

#### Worktree・並行作業

- **H12**: 新作業は Worktree 作成（メインWSでブランチ切り替え禁止）
- **H13**: Worktree 作成 → auto-memory の MEMORY.md（`~/.claude/projects/<slug>/memory/MEMORY.md`）の Active Work セクションに記録（この順序。飛ばさない）
- **H14**: DBマイグレーション作業の並行禁止

#### ORM_TYPE=prisma の場合のみ有効

- **H3**: `prisma db push` 禁止
- **H4**: `prisma migrate deploy/dev` は Claude 自律実行禁止

#### コミット

- **H15**: コミット本文に 背景/対応/影響 必須（自明な変更でも省略しない）

---

### 自動実行の制御方式: ブラックリスト

**原則: 禁止・承認必須に該当しないものは全て自動実行。**
ホワイトリスト（許可リスト）ではなくブラックリスト（禁止リスト）で制御する。
（ADR-0002「ブラックリスト方式」参照）

#### 禁止（hooks で物理ブロック。例外なし）

| 操作 | ブロック手段 | 対応するHARDルール |
|------|-------------|------------------|
| PRD DB への書き込み | guard-db-operation.sh | H2, H6 |
| 保護ブランチへの直接 push | guard-bash.sh | H9 |
| `.env` の `DATABASE_URL` 変更 | guard-bash.sh | H5 |
| `rm -rf` / 再帰削除 | guard-bash.sh | — |
| `prisma db push` | guard-bash.sh | H3 |
| メインWSでの `git checkout` | guard-bash.sh | H12 |
| 公開ファイルへの PII 混入（commit 時） | .claude/githooks/pre-commit | pii-prevention.md (HARD) |

#### 承認必須（不可逆な操作。確認なしで実行しない）

- git push（全ブランチ） → **H7**
- PR 作成・マージ・クローズ → **H8**
- PRD DB マイグレーション → **H4**
- PRD DB SELECT（読み取りでも確認必須）
- STG DB マイグレーション実行
- STG DB データ変更（INSERT / UPDATE / DELETE）
- 破壊的操作（ファイル削除、ブランチ削除、force push）
- `git stash` / `git reset` / `git rebase`
- **確認時は必ず「何を承認するのか」を明記する**（ブランチ名＋変更内容＋対象環境）

#### それ以外 → 全自動（確認不要）

ファイル読み書き、テスト実行、git add/commit/status/diff、Worktree操作、
STG DB SELECT（接続先確認は毎回必須）、その他ローカル操作は全て自律実行OK。

---

### 判断ゲート

#### ゲート1: ルールが関わる操作の前

**トリガー**: git操作、DB操作、デプロイなど、CLAUDE.md にルールが存在する領域での操作

**アクション**: 該当ルールを特定・引用してから実行。ルールに反する場合はルールの枠内で実現する方法を考える。ユーザーの指示がルールと矛盾する場合は確認する

#### ゲート2: 情報の確度表示

**トリガー**: 事実・仕様・技術情報をユーザーに伝える場面

| 確度 | 意味 | 例 |
|------|------|-----|
| **確認済み** | コード・ドキュメント・実行結果で裏取り済み | 「コードを確認しました。この関数は〜」 |
| **推測** | 根拠はあるが未確認 | 「（推測）ログから見るに〜」 |
| **未検証** | 一般知識・経験則 | 「（未検証）一般的には〜」 |

推測・未検証の情報を確定的に述べない。ユーザーの意思決定に影響する情報は必ず確度を添える。

#### ゲート3: CLAUDE.md / auto-memory への記録前

| 記録内容 | 記録先 |
|----------|--------|
| プロジェクトルール・規約 | CLAUDE.md の該当セクションに追記 |
| 設計判断の「なぜ」 | ADR（`docs/decisions/`） |
| 行動修正の経緯 | auto-memory の `feedback_*.md` |
| 外部システムへのポインタ | auto-memory の `reference_*.md` |
| 作業中のステータス・引継ぎメモ | auto-memory の `MEMORY.md`（Active Work / Backlog） |
| 既存セクションのどこにも該当しない | ユーザーに配置を確認する |

---

### 「〜お願いします」の解釈

- 「お願いします」「コミットして」 → **add→commit は確認なしで即実行**
- git status / diff の事前確認ダイアログも不要
- **git push / PR作成 / PRマージは必ず確認してから実行**
- 指示の範囲を超える追加操作は行わない

### 壁打ち・議論の進行ルール

1. **発散**: 選択肢を広げる。批判せず可能性を列挙
2. **収束**: 各選択肢を評価し比較表で整理
3. **決定**: ユーザーの判断を待つ。勝手に決めない

- 壁打ち中は実装に着手しない（「考える」と「作る」を分離）
- 決定後、仕様判断があれば ADR 記録を提案する

### セルフレビュー

作業完了前に `/review` スキルを実行し、セルフチェックを行う。

### ブロック時の通知義務

作業が進められない状況では、**黙って停止せず即座にユーザーに報告する。**

- 自力で解決できそう → 1回だけ試みる → 解決しなければ報告
- 他チャットへの影響・設計判断 → 即座に報告
- 判断に迷う → 報告（報告しすぎは許容、沈黙は許容しない）

```
⚠️ [ブロック / 要確認]
状況: （何が起きているか）
原因: （わかっている範囲で）
影響: （作業にどう影響するか）
選択肢: （ユーザーが選べる対応案）
```

---

## 3. Lessons Learned

### hook スクリプトでの JSON パース

- `echo "$VAR" | jq` を使わない。`printf '%s\n' "$VAR" | jq` を使う
- 理由: `echo` のバックスラッシュ展開は POSIX で未定義。Windows パス（`C:\Users\...`）で jq パースが壊れ、全ガードが無効化される
- jq 呼び出しには `2>/dev/null` を付ける
- jq パース失敗時（変数が空）は grep フォールバックを実装する
