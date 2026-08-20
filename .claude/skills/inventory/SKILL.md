---
name: inventory
description: "タスク棚卸し + sidekickバージョンチェック。Tasks DB・GitHub Issues・Backlogを横断照合し、作業全体像を一覧表示する。"
user-invocable: true
allowed-tools: "Read Grep Glob Bash(git *) Bash(gh *) Agent WebFetch"
---

# /inventory — タスク棚卸し・全体像把握

## 実行方式

このスキルは **Agent ツールで隔離実行する**。
メインコンテキストを保護するため、以下の手順で実行すること:

1. Agent ツールを起動し、このスキルの全手順（Step 1〜7）を渡す
2. Agent はスキルの手順を実行し、Return Contract に従って結果を返す
3. メインコンテキストには結果サマリのみが残る

> **例外**: Step 5 で sidekick バージョン更新の承認が必要な場合、
> Agent は「更新あり」の旨をサマリに含めて返し、メインで承認を求める。

## 目的

複数のタスクソース（Tasks DB、GitHub Issues、auto-memory MEMORY.md Backlog）を横断的に取得・照合し、
現在の作業全体像を一覧表示する。加えて、sidekick テンプレートの更新有無を検知する。

セッション開始時やタスクの優先順位を見直したいときに実行する。

---

## 手順

### Step 1: Tasks DB タスク取得

> **前提条件**: CLAUDE.md の `NOTION_ENABLED` が `true`、かつタスクDB連携の設定ファイル（`.claude/rules/` 配下）が存在する場合のみ実行。
> 該当しない場合はスキップし、Step 2 へ。

Tasks DB から自PJの未完了タスクを取得する。

```
フィルタ条件:
  - Project = 自PJ名（タスクDB連携の設定ファイルに記載）
  - Status = Todo OR Doing OR Waiting
```

取得したタスクを以下の形式で一時保持:

```
[TasksDB] {タスク名} | Status: {status} | Blocker: {blocker_type or なし}
  URL: {notion_url}
  Instruction: {instruction_detail の先頭100文字}
```

### Step 2: PJ固有DB タスク取得

> **前提条件**: CLAUDE.md に PJ固有の Notion DB（Tasks DB 以外）が定義されている場合のみ実行。
> 定義がない場合はスキップし、Step 3 へ。

PJ固有DBの未完了タスクを取得し、同様の形式で一時保持する。

```
[{DB名}] {タスク名} | Status: {status}
  URL: {notion_url}
```

### Step 3: GitHub Issues 取得

リポジトリの Open Issues を取得する。

```bash
gh issue list --state open --limit 50 --json number,title,labels,assignees,createdAt
```

取得した Issues を以下の形式で一時保持:

```
[Issue] #{number} {title} | Labels: {labels} | Assigned: {assignees}
```

Issue がない場合は「GitHub Issues: 0件」と表示してスキップ。

### Step 4: auto-memory MEMORY.md Backlog 読み込み

auto-memory の MEMORY.md（`~/.claude/projects/<slug>/memory/MEMORY.md`）の `## Backlog` セクションを読み込み、未完了項目（`- [ ]`）を一時保持する。

```
[Backlog] {内容}
```

### Step 5: sidekick バージョンチェック（軽量 — Critical のみ強調）

> **前提条件**: `CLAUDE.md` の Project Configuration に `SIDEKICK_VERSION` が設定されている場合のみ実行。
> sidekick をテンプレートとして利用していないPJ（sidekick 自身を含む、`SIDEKICK_VERSION` が空）ではスキップ。

#### 5a. バージョン + severity 取得

```bash
CURRENT=$(grep -E "^SIDEKICK_VERSION:" CLAUDE.md | sed -E 's/.*"([^"]+)".*/\1/')
LATEST=$(gh api repos/SideMountain/claude-code-sidekick/releases/latest --jq '.tag_name')
TITLE=$(gh api repos/SideMountain/claude-code-sidekick/releases/latest --jq '.name')
BODY=$(gh api repos/SideMountain/claude-code-sidekick/releases/latest --jq '.body')

# 第一ソース: body の構造化マーカー（> severity: ...）。printf でパース安全に（CLAUDE.md §3）
MARKER=$(printf '%s\n' "$BODY" | grep -oE 'severity:[[:space:]]*(critical|standard|enhancement)' | head -1 | sed -E 's/.*:[[:space:]]*//')
case "$MARKER" in
  critical)    SEVERITY="Critical" ;;
  enhancement) SEVERITY="Enhancement" ;;
  standard)    SEVERITY="Standard" ;;
  *)  # フォールバック: 旧リリース（v0.8.0 以前、マーカー無し）は title prefix で判定
    case "$TITLE" in
      *"[CRITICAL]"*)    SEVERITY="Critical" ;;
      *"[ENHANCEMENT]"*) SEVERITY="Enhancement" ;;
      *)                 SEVERITY="Standard" ;;
    esac ;;
esac
```

#### 5b. 表示（severity 別）

**Critical の場合のみ強調・即取り込み推奨**:

```
[sidekick] v${CURRENT} → ${LATEST}
  ⚠️  Critical 更新: ${TITLE}
  → 即取り込み推奨: /adopt-sidekick-update
```

**Standard / Enhancement の場合は 1行サマリ**:

```
[sidekick] v${CURRENT} → ${LATEST} (${SEVERITY}) — 詳細は /weekly-inventory、取り込みは /adopt-sidekick-update
```

#### 5c. スキップ済み項目の件数表示

`auto-memory/project_skipped_updates.md` が存在する場合、件数のみ表示（詳細は /adopt-sidekick-update に委譲）:

```
  スキップ済み: 永久 X件 / 後回し Y件
```

#### 5d. Critical 未取込フラグの書き込み（ADR-0009 P3）

Critical 更新を検知した場合、auto-memory に `project_critical_pending.md` を作成/更新する:

```bash
if [ "$SEVERITY" = "Critical" ]; then
  MEM_DIR="$HOME/.claude/projects/$(pwd | sed 's|/|-|g')/memory"
  mkdir -p "$MEM_DIR"
  cat > "$MEM_DIR/project_critical_pending.md" <<EOF
# Critical sidekick release pending

- release: ${LATEST}
  title: ${TITLE}
  detected_at: $(date -Iseconds)
  source: /inventory
EOF
fi
```

このフラグは `session-start.sh` が毎セッション開始時に読み、**取り込み忘れ防止の warning** を表示する。
`/adopt-sidekick-update` が Critical を取り込むとフラグが削除される（3層の「検知」）。

**設計意図**: `/inventory` は高頻度実行なので**冗長化を避け、緊急情報のみ強調**する。Standard/Enhancement の詳細棚卸しは `/weekly-inventory` の責務（ADR-0009）。

#### 5e. 配布完結性チェック（read-only・欠落は毎回出す）

取り込み済みバージョンが最新でも、**配布が完結しているとは限らない**。`/adopt-sidekick-update` が配るのは差分であって closure ではないため、SKILL.md だけが届いて companion（そのスキルが叩くスクリプト・Read する規範ファイル）が欠けたままの PJ が実在する。この状態のスキルは**エラーを出さずに dimension を落とす**ので、定期実行される `/inventory` が検知役を持つ。

`/inventory` は read-only なので補修しない（`--repair-from` は付けない）。判定は共有ゲートに委ねる:

```bash
GATE=.claude/scripts/distribution-gate.sh
if [ -f "$GATE" ]; then
  # ここは代入の形で status を受けてよい（$? は代入＝コマンド置換の status
  # なのでゲートの exit がそのまま入る）。/review Step 0・/adopt Step 6.6 と
  # 違い、**意図的に非 0 を伝播させない** — 棚卸しの他の結果は有用なので
  # 中断しない。その代わり Step 7 で必ず可視化し、「問題なし」とは書かない。
  DIST_OUT=$(bash "$GATE" 2>&1); DIST_ST=$?
else
  DIST_OUT="[EVIDENCE_REQUIRED] $GATE 自体が未配置"; DIST_ST=5
fi
```

| exit | Step 7 での扱い |
|---|---|
| 0 | 表示しない（無音が既定・軽さドクトリン） |
| 3 | 欠落一覧を出し、推奨アクションに **`/adopt-sidekick-update`** を載せる |
| 4 / 5 / 6 / 7 / **その他** | 「判定不能」として出す。**0 と同じ扱いにしない** — 検査器自身の未配置がここに来るため、無音にすると欠落が構造的に見えなくなる |

`/inventory` は報告のみで停止しない（棚卸しの他の結果は有用なため）が、**「配布は問題なし」とは書かない**。0 以外は必ず一覧に残す。

### Step 6: 重複検知

Step 1-4 で取得した全タスクを横断照合し、類似タスクを検出する。

**照合ロジック:**
- タスク名のキーワード一致（部分一致）
- 同一ファイル・同一機能への言及

重複候補がある場合:
```
⚠️ 重複の可能性:
  [TasksDB] "○○機能の実装" ↔ [Issue] #3 "○○を追加"
  → 同一タスクの場合、どちらかをクローズしてください
```

重複がない場合は報告不要。

### Step 7: 統合一覧表示

全ソースのタスクを統合し、以下のフォーマットで表示する。

```
=== /inventory 結果 ===

[Tasks DB] X件（Todo: X, Doing: X, Waiting: X）
  1. {タスク名} [Status] — {instruction 要約}
  2. ...

[PJ固有DB] X件（該当する場合のみ表示）
  1. ...

[GitHub Issues] X件
  1. #{number} {title} [{labels}]
  2. ...

[Backlog] X件（未完了）
  Phase 0: X件（完了/未完了）
  Phase 1: X件
  ...

[sidekick] v{current} （最新: v{latest} — 更新あり/最新です）

[配布完結性] 完結 / 欠落 X件（該当時のみ表示） / 判定不能（検査器未配置）

[重複検知] X件の候補（ある場合のみ）

===========================
推奨アクション:
  - {最も優先度の高いタスクの提案}
  - {ブロッカーがある場合の対応提案}
```

---

## 実行タイミング

- **セッション開始時**: チャット開始時の状況把握
- **手動**: ユーザーが `/inventory` を呼び出したとき
- **cron（将来）**: 毎朝の自動実行（ADR-0003 で計画済み）

## 注意事項

- Tasks DB / PJ固有DB へのアクセスは**読み取りのみ**。書き込みは行わない
- GitHub Issues が大量にある場合は `--limit 50` で制限する
- 重複検知は目安。最終判断はユーザーに委ねる
- sidekick バージョンチェックで差分適用する場合、変更内容を確認してからコミットする

---

## Return Contract

### 返すもの
- Step 7 の統合一覧（ソース別件数 + タスク一覧）
- 重複検知結果（ある場合のみ）
- sidekick バージョン差分情報（更新がある場合のみ）
- 推奨アクション

### 返さないもの
- Notion API / GitHub API の呼び出しログ
- 照合の途中経過（マッチング判定の詳細）
- 取得した生データ（JSON レスポンス等）
