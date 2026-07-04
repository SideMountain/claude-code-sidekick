---
name: setup
description: "プロジェクトセットアップ。新規PJはテンプレートから生成、既存PJは非侵襲的に追加する。"
user-invocable: true
allowed-tools: "Read Write Edit Bash(git *) Bash(cp *) Bash(grep *) Bash(claude *) Glob"
---

# /setup — プロジェクトセットアップ

## 目的

新規または既存プロジェクトの Claude Code 環境を対話的にセットアップする。
ヒアリングから設定ファイル生成、個人設定初期化までを一貫して行う。

## 設計原則

- **何もしないがデフォルト** — 追加したいものだけ opt-in で聞く
- **既存ファイルを上書きしない** — 差分を提示してユーザーに確認する
- **背景知識不要** — 質問は「何がしたいか」で聞く（sidekick の内部構造を前提にしない）
- **.gitignore は配置と連動** — 配置しなかったファイルの gitignore パターンは追記しない

---

## 手順

### Step 0: モード判定

```
CLAUDE.md が既に存在するか？
  ├── No → 新規PJモード（Step 1 へ）
  └── Yes → 既存PJモード（Step 1E へ）
```

---

## 新規PJモード

### Step 0.5: テンプレートクリーンアップ

GitHub Template から fork した場合、sidekick 自身のファイルがルートに残っている。
以下のファイルの扱いをユーザーに確認する:

| ファイル | デフォルト案内 |
|---------|-------------|
| `CHANGELOG.md` | 「これは sidekick のリリース履歴です。削除して、プロジェクト固有の CHANGELOG を必要に応じて作成してください」 |
| `README.md` / `README.ja.md` | 「プロジェクト固有の README に差し替えてください」 |
| `.github/` | 「Issue テンプレートをそのまま使いますか？カスタマイズしますか？不要なら削除できます」 |
| `LICENSE` | 「プロジェクトのライセンスに差し替えてください」 |
| `docs/decisions/` | **sidekick 由来 ADR は自動削除対象**（ADR-0014/0015 により下流 PJ には sidekick の ADR を配布しない）。`README.md` と `_template.md` のみ残し、番号付き ADR ファイル（`NNNN-*.md`）は全て削除する。下流 PJ が独自 ADR を書く空のディレクトリとして残す |

> **判定方法**: `CHANGELOG.md` の冒頭が `# Changelog` かつ `sidekick` を含む場合、テンプレートから fork と判定する。
> 該当しない場合（既存PJモードでもない）はスキップ。

> **`docs/decisions/` の自動削除**: テンプレート fork 判定時、以下のコマンドで sidekick 由来 ADR を一括削除する。

```bash
# sidekick 由来の番号付き ADR を削除（README.md と _template.md は残す）
find docs/decisions -maxdepth 1 -type f -name '????-*.md' -delete

# README.md がある場合は ADR 索引を空のテーブルに初期化
if [ -f docs/decisions/README.md ]; then
  cat > docs/decisions/README.md <<'EOF'
# Architecture Decision Records (ADR)

このディレクトリにはプロジェクトの仕様判断を記録する ADR を格納する。

## ADR一覧

| 番号 | タイトル | ステータス | 日付 |
|------|---------|----------|------|
| (未記録) | — | — | — |

## ADRとは

- 仕様レベルの判断を記録するドキュメント
- 「なぜこう決めたか」を後から参照可能にする
- `/record-decision` スキルで作成する
EOF
fi
```

### Step 1: ヒアリング

以下の項目をユーザーに確認する。全て埋まるまで次のステップに進まない。

**必須項目:**

| 項目 | 質問 | 例 |
|---|---|---|
| プロジェクト名 | 何を作りますか？ | ECサイト、SaaS管理画面、API |
| 言語/FW | 使用する言語とフレームワークは？ | Next.js + TypeScript, Rails, Go + Echo |
| DB | DBは使いますか？ORM は？ | PostgreSQL + Prisma, MySQL + Drizzle, なし |
| ホスティング | デプロイ先は？ | Vercel, AWS, GCP, 自前サーバー |
| テスト | テストフレームワークは？ | Vitest, Jest, RSpec, go test |
| チーム規模 | 何人で開発しますか？ | 1人, 2-3人, 5人以上 |

**オプション項目:**

| 項目 | 質問 | デフォルト |
|---|---|---|
| MCP連携 | Notion, Slack, Sentry 等の MCP を使いますか？ | なし |
| ブランチ戦略 | Git-flow? GitHub-flow? | GitHub-flow（main + feature） |
| CI/CD | GitHub Actions? | なし |
| コミット規約 | Conventional Commits? | はい |

MCP を使う場合、`.claude/skills/setup/references/mcp-recommendations.md` を読み、
Tier に応じたインストールコマンドを案内する。

### Step 2: Project Configuration の設定

ヒアリング結果を基に以下のファイルを生成・更新する。

#### 2a. CLAUDE.md の生成

CLAUDE.md の `Project Configuration` をヒアリング結果で埋める。

設定項目（Project Configuration の yaml 値を埋める）:
- `PROJECT_NAME`, `LANGUAGE`, `PACKAGE_MANAGER`
- `STG_ENABLED`, `PROTECTED_BRANCHES`（ブランチ戦略。詳細は rules/git-strategy.md）
- `TEST_COMMAND`, `TYPECHECK_COMMAND`, `BUILD_COMMAND`, `LINT_COMMAND`
- `ORM_TYPE`, `STG_DB_PATTERN`, `PRD_DB_PATTERN`（DB設定。詳細は rules/database.md）
- `NOTION_ENABLED`
- `SIDEKICK_VERSION`（このPJを生成した ccs テンプレートのバージョン。ここでは空のまま。Step 3.6 で ccs remote の最新タグから自動スタンプする。空のままだと `/inventory`・`/adopt-sidekick-update` のバージョンチェックがスキップされる）

#### 2b. .claude/settings.local.json の生成

プロジェクトに応じた allow/deny リストを設定する。
また、**Worktree のディレクトリアクセス許可**のため、プロジェクトの親ディレクトリを `additionalDirectories` に自動設定する。

```bash
# 親ディレクトリの絶対パスを取得
PARENT_DIR=$(cd .. && pwd)
```

```json
{
  "permissions": {
    "allow": ["テストコマンド", "ビルドコマンド", "リントコマンド"],
    "deny": ["本番DB操作コマンド"],
    "additionalDirectories": [
      "<PARENT_DIR の値>"
    ]
  }
}
```

> **なぜ**: Worktree は `../<project>-<用途>` に作成される。親ディレクトリを信頼対象にしないと、
> WT内のファイル操作時にツール許可（Allow）とは別軸のディレクトリアクセス確認ダイアログが毎回表示される。
> `settings.local.json` は git 非追跡なので、マシン固有のパスが入っても問題ない。
>
> **`/add-dir` との関係**: `/add-dir` はセッション単位の一時的な許可。`additionalDirectories` は永続設定。
> `/setup` で後者を設定済みなら、rules/git-strategy.md Worktree 手順のステップ1.5（`/add-dir`）は省略できる。
>
> **注意**: 親ディレクトリ配下の他プロジェクトもアクセス対象になる。
> 秘匿情報を含むプロジェクトが同階層にある場合は、WT専用の親ディレクトリで運用することを推奨。

#### 2c. スキル設定の調整

PJの特性に応じてスキルの活用方針を案内する:
- DB を使わないPJでは review-code の DB 観点をスキップ対象とする
- auto-implement の適用範囲を案内する（「推奨ユースケース」セクション参照）

#### 2d. PII pre-commit hook の有効化（core.hooksPath）

`.claude/githooks/pre-commit`（PII 強制層、`.claude/rules/pii-prevention.md` の enforcement 実装）を有効化する。
`core.hooksPath` は git 非追跡の per-repo 設定なので、clone ごとに 1 回必要:

```bash
git config core.hooksPath .claude/githooks
echo "PII pre-commit hook を有効化しました（公開ファイルへの PII 混入を commit 時に物理ブロック）"
```

> **注意**: `core.hooksPath` は `.git/hooks/` を置き換える。既に独自 git hook を `.git/hooks/` に持つ PJ では、それらを `.claude/githooks/` に移すか統合する。
> **PJ 固有名のカスタマイズ**: `.claude/githooks/pre-commit` 末尾のコメント部に、当該 PJ の人名・PJ名・接続先パターンを追記する（`pii-prevention.md` の scan_pii と同じ運用）。
> **既存PJモードでも同様**: Step 1E で `core.hooksPath` 未設定なら設定する。worktree は共通 git config を参照するため、設定は全 worktree に効く。

### Step 3: テンプレート配置

`.claude/templates/` から必要なファイルをルートにコピーする。

#### 3a. CLAUDE.local.md（opt-in）

「個人設定ファイル（応答言語・ローカル環境メモ）を使いますか？」と確認。
Yes の場合:
```bash
cp .claude/templates/CLAUDE.local.md CLAUDE.local.md
```

#### 3b. .gitattributes

`.gitattributes` が存在しない場合は自動配置する（確認不要）。
Windows 環境での CRLF 問題を防ぐため、シェルスクリプトの LF を強制する。
```bash
cp .claude/templates/.gitattributes .gitattributes
```

#### 3c. GitHub テンプレート（opt-in）

「GitHub Issue テンプレート（バグ報告・機能要求）とラベル定義を追加しますか？」と確認。
Yes の場合:
```bash
cp -r .claude/templates/github/.  .github/
```

#### 3d. Next.js stack pack（opt-in・ADR-0021）

**Next.js を検知した場合のみ確認する**（非 Next PJ には聞かない＝無コスト）:

```bash
if [ -f package.json ] && grep -q '"next"' package.json 2>/dev/null; then
  echo "Next.js を検知しました（stack pack opt-in を確認します）"
elif [ ! -f package.json ]; then
  echo "package.json がまだありません（テンプレ生成直後）。Next.js PJ かを直接確認します"
fi
```

> **chicken-and-egg に注意**: テンプレから生成した直後のリポは `package.json` が無く、`next` 検知が
> 滑る。その場合は**自動検知に頼らず「Next.js + Prisma のプロジェクトですか？」と直接ユーザーに聞く**
> （Yes なら下記の opt-in に進む）。後から `create-next-app` した後でも、CLAUDE.md を手動で
> `STACK_PACK: nextjs` にすれば有効化できる。

検知時（または直接確認で Yes 時）、こう確認する:
「**Next.js stack pack** を有効にしますか？ 規定アーキ（golden path）+ `system-map` 可視化を提供します。下流PJを一貫した構造に保ち、コードベースを画面↔API↔DB↔権限↔遷移の単一HTML地図に決定的に可視化できます。」

**Yes の場合:**
- CLAUDE.md Project Configuration の `STACK_PACK: none` を `STACK_PACK: nextjs` に変更。
- Prisma 利用なら `ORM_TYPE: prisma` も併せて提案（golden path は Prisma 前提）。
- 案内する（**認知 → 強制 → 検知の一式・v0.12.0**）:
  - **認知**: 実装・レビューの規約は `.claude/stack-packs/nextjs/ARCHITECTURE.md`（Tier-1 STRUCTURAL / Tier-2 HYGIENE）。
  - **強制（生成）**: 規約準拠のアプリ骨格を `node .claude/stack-packs/nextjs/scaffold/scaffold.js <targetDir>` で展開（`posts` 縦スライスが手本。**pack は Next アプリ本体を作らないので先に `create-next-app` 等で土台を用意**）。詳細 `.claude/stack-packs/nextjs/scaffold/README.md`。
  - **検知**: `package.json` に `"test:arch": "node .claude/stack-packs/nextjs/fitness-functions/run-fitness.js ."` を追加して CI に挿す（error=HARD で落とす / warn=SOFT）。S1 循環依存は対象外ゆえ `madge --circular` を別ステップで補う。詳細 `.claude/stack-packs/nextjs/fitness-functions/README.md`。
  - **可視化**: `system-map` スキル。出自・roadmap は `.claude/stack-packs/nextjs/README.md`、設計判断は ADR-0021。
  - 立ち上げの通し手順は README の「Building a Next.js + Prisma project」節を案内する。

**No の場合:** `STACK_PACK: none` のまま（後から CLAUDE.md を手動で `nextjs` にすれば有効化できる）。

> **非 Next PJ への配布**: stack pack のファイル（`.claude/stack-packs/`）は配布物に含まれるが、`STACK_PACK: none` の PJ では CLAUDE.md・skills 側がこのレイヤーを参照しない（opt-in gate）。物理的に不要なら削除してよい。

### Step 3.5: ccs remote 追加（新規PJモード）

下流 PJ が `/adopt-sidekick-update` で sidekick の更新を取り込めるよう、claude-code-sidekick を remote として登録する:

```bash
if ! git remote | grep -q "^ccs$"; then
  git remote add ccs https://github.com/SideMountain/claude-code-sidekick.git
  git fetch ccs --tags 2>/dev/null
  echo "ccs remote を追加しました（/adopt-sidekick-update で使用）"
fi
```

**既存PJモードでも同様**: Step 1E の確認項目に `ccs remote の有無` を追加し、未設定なら自動追加（ADR-0009）。

### Step 3.6: SIDEKICK_VERSION のスタンプ（新規PJモード）

生成した CLAUDE.md の `SIDEKICK_VERSION` を、このPJを生成した ccs テンプレートのバージョンで埋める。
これを省略すると `SIDEKICK_VERSION: ""` のままになり、`/inventory` のバージョンチェックと
`/adopt-sidekick-update`（いずれも非空を前提）が永久にスキップされ、新規PJが更新を取り込めなくなる。

> **バージョンの取得元**: ccs remote の最新タグを正とする。GitHub Template fork は git タグを
> 引き継がないためローカルの `git describe` は当てにできない。Step 3.5 で追加・fetch 済みの
> `ccs` remote のタグを参照する（Step 4.5 の個人 brain 初期化と同じ取得経路）。

```bash
git fetch ccs --tags 2>/dev/null
CCS_TAG=$(git ls-remote --tags ccs 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
if [ -n "$CCS_TAG" ]; then
  # SIDEKICK_VERSION は v プレフィックスなしで格納（例: "0.8.0"）
  sed -i 's/^SIDEKICK_VERSION: .*/SIDEKICK_VERSION: "'"${CCS_TAG#v}"'"/' CLAUDE.md
  echo "SIDEKICK_VERSION を ${CCS_TAG#v} に設定しました（このPJは ccs ${CCS_TAG} から生成）"
else
  echo "⚠️  ccs remote にタグが見つかりません。SIDEKICK_VERSION は空のままです。"
  echo "   ccs remote 追加後（Step 3.5）に /setup を再実行するか、手動で CLAUDE.md の"
  echo "   SIDEKICK_VERSION を最新リリース番号に設定してください（空のままだと /inventory・"
  echo "   /adopt-sidekick-update のバージョンチェックがスキップされます）。"
fi
```

> **既存PJモードでも同様**: Step 1E で `SIDEKICK_VERSION` が空（テンプレート初期値のまま）と判明した
> 場合のみ、上記と同じロジックで ccs 最新タグからスタンプする（本 fix 以前に取り込んで空のまま
> deadlock している既存PJの救済）。**既に非空の値が入っている PJ は上書きしない**（意図的な
> version pin を壊さないため）。

### Step 4: .gitignore 連動

**Step 3 で配置したファイルに対応するパターンのみ追記する。**

必ず追記するもの（sidekick コアが必要とする）:
- `.env`, `.env.local`
- `.claude/settings.local.json`
- `.claude/agent-memory-local/`
- `.claude/skills/*/.data/`

Step 3 で配置した場合のみ追記:
- CLAUDE.local.md を配置した → `CLAUDE.local.md`

外部DB連携を設定した場合のみ追記:
- `.claude/rules/task-db-integration.md`

### Step 4.5: brain (思考OS) のセットアップ

判断基盤の格納先を 2 層構造で設定する（ADR-0016）。

| 層 | 配置 | スコープ | ロード対象 |
|---|---|---|---|
| 個人 brain | `~/.claude/brain/thinking.md` | 個人（複数 PJ 横断）。利用者が育てる | ✅ |
| PJ 固有 brain | `<PJ>/.claude/brain/thinking.md` | この PJ 固有 | ✅ |

OSS テンプレート（sidekick の `brain/thinking.md`）は配布素材としてリポに含まれるが、ロード対象ではない。`/setup` が個人 brain 不在時のみコピー元として利用する。

#### 個人 brain の初期化（不在時のみ、上書き禁止）

```bash
PERSONAL_BRAIN="$HOME/.claude/brain/thinking.md"

if [ ! -f "$PERSONAL_BRAIN" ]; then
  mkdir -p "$HOME/.claude/brain"

  # テンプレート取得: ローカル優先（新規 PJ モード時の fork 直後）、なければ ccs remote から
  if [ -f "brain/thinking.md" ]; then
    cp "brain/thinking.md" "$PERSONAL_BRAIN"
    echo "個人 brain を初期化しました（ローカル brain/thinking.md からコピー）: $PERSONAL_BRAIN"
  elif git remote | grep -q "^ccs$"; then
    git fetch ccs --tags 2>/dev/null
    LATEST_TAG=$(git ls-remote --tags ccs 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
    if [ -n "$LATEST_TAG" ]; then
      git show "${LATEST_TAG}:brain/thinking.md" > "$PERSONAL_BRAIN" 2>/dev/null \
        && echo "個人 brain を初期化しました（ccs ${LATEST_TAG} からコピー）: $PERSONAL_BRAIN" \
        || echo "⚠️  ccs ${LATEST_TAG} から brain/thinking.md を取得できませんでした"
    else
      echo "⚠️  ccs remote にタグが見つかりません。/inventory でリリース確認後、再実行してください"
    fi
  else
    echo "⚠️  ローカル brain/thinking.md も ccs remote も見つかりません"
    echo "   Step 3.5 で ccs remote を追加後、再実行してください"
  fi
  echo "（今後は利用者が育てる、自動上書きしない）"
else
  echo "個人 brain は既に存在: $PERSONAL_BRAIN（触らない）"
fi
```

**重要: 既存の個人 brain は絶対に上書きしない**。育てた判断軸を失う事故を防ぐ。
OSS テンプレートに更新があった場合の取り込みは `/adopt-sidekick-update` 経由で対話的に行う（自動上書きしない）。

#### PJ 固有 brain の配置

`<PJ>/.claude/brain/thinking.md` を配置する。**既存ファイルがあれば上書きしない**（fork 由来 / 既に育てた PJ brain を保護）。冒頭で個人 brain を 1 段 import する薄いファイルを決定論的に生成する:

```bash
PJ_BRAIN=".claude/brain/thinking.md"

if [ ! -f "$PJ_BRAIN" ]; then
  mkdir -p ".claude/brain"
  # PROJECT_NAME を CLAUDE.md から取得（未設定なら汎用名）
  PROJECT_NAME=$(grep -E '^PROJECT_NAME:' CLAUDE.md 2>/dev/null | sed -E 's/.*"([^"]*)".*/\1/')
  [ -z "$PROJECT_NAME" ] && PROJECT_NAME="this project"
  cat > "$PJ_BRAIN" <<EOF
# brain — ${PROJECT_NAME} PJ 固有 brain

@~/.claude/brain/thinking.md

> このファイルは ${PROJECT_NAME} PJ 固有の判断軸を保持する。
> 上記 @import で個人 brain を取り込む。個人 brain 不在時は silent ignore され、PJ brain だけがロードされる。
> 2 層 brain モデルの詳細は ADR-0016 を参照。
EOF
  echo "PJ 固有 brain を生成しました: $PJ_BRAIN"
else
  echo "PJ 固有 brain は既に存在: $PJ_BRAIN（触らない）"
fi
```

PJ 固有判断軸は本ファイル下部に追記する（Step 5 で対話的に記入）。

CLAUDE.md §1 は `@.claude/brain/thinking.md` で PJ brain を取り込む。PJ brain が個人 brain を transitive import する 1 段構造。

### Step 5: オーナー情報の記録（任意・全スキップ可）

> 「全スキップ」と言われたら即 Step 6 へ。使いながら自然に蓄積される設計なので、ここで埋まらなくても問題ない。

PJ 固有 brain のカスタマイズ用。選択肢から選ぶか、自由記入か、スキップ。

| 質問 | 選択肢の例 | 記録先 |
|---|---|---|
| 設計で重視すること | シンプルさ / パフォーマンス / 拡張性 / 堅牢性 / 自由記入 | PJ brain §1 |
| 判断スピード | 70%で動く / 慎重派 / 状況による / 自由記入 | PJ brain §1 |
| 技術的負債への態度 | 返す派 / 動けば良い / 重要箇所だけ / 自由記入 | PJ brain §1 |
| テスト方針 | TDD / 後追い / 重要箇所のみ / 書かない / 自由記入 | CLAUDE.md |
| ドキュメント管理 | Notion / Google Docs / docs/ だけ / なし | rules/documentation.md |

回答があれば `.claude/brain/thinking.md`（PJ brain）§1 に反映する。なければ import のみの薄い PJ brain のまま。
複数 PJ で同じ判断をする場合は個人 brain（`~/.claude/brain/thinking.md`）に書く方が DRY。判定基準: 「全 PJ で適用したい判断軸か?」 YES → 個人 brain、NO → PJ brain。

### Step 5.5: 外部DB連携（オプション）

> **ほとんどのPJではスキップ可。** Notion等と連携したい場合のみ設定する。
> sidekick は auto-memory + GitHub Issues だけで全機能動作する。

連携したい場合:
1. `.claude/rules/task-db-integration.md.example` をコピーして設定を記入
2. Notion MCP が有効か確認（`claude mcp list`）
3. CLAUDE.md の `NOTION_ENABLED: true` に変更

### Step 5.8: budget-gate 稼働検証（ADR-0025 follow-up・検知のみ）

capturer の配線と正準ファイルの鮮度を検査し、稼働状態を明示する。**休眠でもブロックしない**（Stop hook は fail-open で安全。「効いているつもり」の防止が目的）:

```bash
RATE_FILE="${CCS_CACHE_DIR:-$HOME/.claude/.cache}/ccs-rate-limits.json"
WIRED=$(grep -l "ccs-rate-capture" ~/.claude/settings.json .claude/settings.json .claude/settings.local.json 2>/dev/null)
CAP=$(grep -o '"captured_at":[0-9]*' "$RATE_FILE" 2>/dev/null | grep -o '[0-9]*$')
AGE=$(( $(date +%s) - ${CAP:-0} ))
if [ -n "$CAP" ] && [ "$AGE" -ge 0 ] && [ "$AGE" -le "${CCS_BUDGET_STALE_SECS:-1800}" ]; then
  printf 'budget-gate: 稼働中（正準ファイル fresh、%s 秒前に capture）\n' "$AGE"
elif [ -z "$WIRED" ]; then
  printf 'budget-gate: 休眠（capturer 未配線 — statusLine に .claude/statusline/ccs-rate-capture.sh を挟むと有効化）\n'
elif [ -z "$CAP" ]; then
  printf 'budget-gate: 休眠（正準ファイル不在 — capturer 配線済だが未 capture。セッション再起動後に生成される）\n'
else
  printf 'budget-gate: 休眠（正準ファイル stale: %s 秒前 — capturer が動いていない可能性）\n' "$AGE"
fi
```

### Step 6: 有効ルール確認 + 完了

Project Configuration に基づいて有効な HARD ルールを一覧表示する:

```
=== 有効な HARD ルール ===
常時有効: H1, H2, H6, H7, H8, H9, H12, H13, H14, H15
ORM_TYPE=prisma: H3, H4（有効/無効）
STG_ENABLED=true: H10, H11（有効/無効）
.env保護(STG/PRD設定時): H5（有効/無効）
```

セットアップ完了サマリを提示:

```
=== セットアップ完了 ===

プロジェクト: {name}
Tech Stack: {language} + {framework} + {db}
ブランチ戦略: {strategy}
テストコマンド: {test_command}

生成/更新したファイル:
- {配置したファイル一覧}

使えるスキル:
  日常:    /review（コード・テスト・運用レビュー）
           /close-chat（セッション終了時の引き継ぎ）
           /news（最新変更のサマリ）
  自動化:  /auto-implement（設計確定済みの作業を全自動実行）
  管理:    /inventory（タスク棚卸し）
           /weekly-inventory（定期メンテナンス）
           /record-decision（設計判断の ADR 記録）

次のステップ:
1. CLAUDE.md の内容を確認し、必要に応じて調整してください
2. `git add . && git commit` でセットアップをコミットしてください
3. 開発を始めましょう
```

---

## 既存PJモード

CLAUDE.md が既に存在する場合。既存のファイルを尊重し、opt-in で追加のみ行う。

### Step 1E: 現状確認

既存PJの状態を調査する:

```
確認項目:
- CLAUDE.md の Project Configuration 内容（SIDEKICK_VERSION 含む）
- .gitignore の sidekick 関連パターンの有無
- CLAUDE.local.md の有無
- .github/ の有無
- .claude/settings.local.json の有無
- settings.local.json に additionalDirectories（WT用）が設定されているか
- ccs remote（/adopt-sidekick-update 用）の有無（ADR-0009）
- `.claude/brain/thinking.md` の有無、`.claude/rules/thinking.md` の有無（brain 移行状態の判定、ADR-0016）
- `~/.claude/brain/thinking.md`（個人 brain）の有無（不在なら初期化候補、存在すれば触らない）
```

### Step 2E: 差分案内

不足しているファイル・設定を一覧表示し、各項目を opt-in で確認する。

```
=== sidekick セットアップ（既存PJモード） ===

✅ 既に存在: CLAUDE.md, .claude/settings.json
❌ 不足: CLAUDE.local.md, .gitignore パターン

以下を追加しますか？（個別に確認します）
```

#### 確認項目:

| 不足 | 質問（背景知識不要な聞き方） | Yes の場合 |
|------|---------------------------|-----------|
| CLAUDE.local.md | 「個人の応答設定（言語等）をカスタマイズしたいですか？」 | `.claude/templates/CLAUDE.local.md` → `CLAUDE.local.md` にコピー |
| .github/ テンプレート | 「GitHub Issue テンプレートを追加しますか？」 | `.claude/templates/github/` → `.github/` にコピー（既存 .github/ がある場合はマージ方法を確認） |
| .gitignore パターン | 上記で配置したファイルに応じて自動追記 | 新規PJモードの Step 4 と同じロジック |
| settings.local.json | 「テスト・ビルドコマンドの自動許可設定を追加しますか？」 | 新規PJモードの Step 2b と同じ |
| additionalDirectories | （確認不要・自動設定） | settings.local.json に親ディレクトリを追加（Step 2b 参照） |
| brain (2 層構造) | 「判断基盤を 2 層モデル（個人 brain + PJ 固有 brain）に移行しますか？」（旧 `.claude/rules/thinking.md` または旧 3 層 chain を保持中の PJ のみ） | 新規PJモードの Step 4.5 と同じ。旧 thinking.md は過渡期は共存可、強制移行は行わない。**既存の個人 brain は絶対上書きしない** |
| 個人 brain (`~/.claude/brain/thinking.md`) 不在 | （確認不要・自動提案） | Step 4.5 の個人 brain 初期化ロジックを実行（OSS テンプレート → home コピー、不在時のみ） |
| `SIDEKICK_VERSION` が空 | （確認不要・自動提案） | 空（テンプレート初期値）なら Step 3.6 のロジックで ccs 最新タグからスタンプ。非空なら触らない（version pin を尊重）。空のまま放置すると `/inventory`・`/adopt-sidekick-update` がスキップされ更新を取り込めない |

### Step 3E: オーナー情報（任意）

新規PJモードの Step 5 と同じ。全スキップ可。

### Step 4E: 完了サマリ

```
=== セットアップ完了（既存PJモード） ===

追加したファイル:
- {配置したファイル一覧}

追加した .gitignore パターン:
- {追記したパターン一覧}

既存ファイル（変更なし）:
- CLAUDE.md
- {その他既存ファイル}
```

---

## 注意事項

- ヒアリングは対話的に進める。一度に全項目を聞かず、カテゴリごとに確認してもよい
- 既に CLAUDE.md が存在する場合は上書きせず、差分を提示してユーザーに確認する
- .github/ が既に存在する場合は、上書きせずマージ方法（追加のみ/個別選択）を確認する
- テンプレートの全セクションを埋める必要はない。プロジェクトに不要なセクションは「対象外」と明記する