# sidekick

**Claude Code を「安全に」「賢く」使うためのハーネステンプレート**

安全フック、再利用スキル、学習する記憶 ― AI があなたのルールで動く。寝ている間に Issue が PR になる。

---

## なぜ sidekick が必要か？

Claude Code はそのままだと強力だが危険。一つの間違いで本番に push、テーブルを DROP、`.env` を上書きしうる。しかも記憶が持続しないので、毎回ゼロからスタート。

sidekick は3つのレイヤーでこれを解決する:

```
レイヤー1: 安全       → hooks が危険な操作を物理ブロック
レイヤー2: スキル     → 再利用可能なワークフロー（レビュー、セットアップ、自動実装）
レイヤー3: 知識       → feedback → 原則 → 思考OS（使うほど賢くなる）
```

### sidekick なし

```
あなた: 「ログインのバグ直して」
Claude: *.env を変更* *main に push* *テストデータ消去*
あなた: 「...」
```

### sidekick あり

```
あなた: 「ログインのバグ直して」
Claude: → Worktree 作成（main は触らない）
        → DB 接続先確認（ステージング確認済み）
        → 修正 → スコープ限定テスト実行
        → /review（コード + テスト + 運用）
        → PR 作成（マージはあなたの判断）
```

---

## クイックスタート

### 新規プロジェクト（テンプレートから）

```bash
# 1. テンプレートからリポジトリ作成
gh repo create my-project --template SideMountain/claude-code-sidekick

# 2. セットアップ
cd my-project
claude  # /setup を実行
```

### 既存プロジェクトに導入

```bash
# 1. コアファイルをコピー
cp -r sidekick/CLAUDE.md sidekick/.claude/ your-project/

# 2. 設定 — /setup が残り（MEMORY.md, .gitignore, テンプレート）を全て処理
cd your-project && claude  # /setup を実行
```

**Tip**: 運用保守フェーズのプロジェクトには、まず安全ガード（hooks + HARDルール）と `/review` だけ導入するのがおすすめ。

---

## 仕組み

### 安全: 3層防御

```mermaid
flowchart LR
    OP["🤖 Claude の\n操作"] --> L1
    subgraph L1["📋 認知"]
        A["CLAUDE.md\nHARD / SOFT / GUIDE"]
    end
    L1 --> L2
    subgraph L2["🛡️ 強制"]
        B["Pre-tool Hooks\nguard-bash.sh\nJSON deny = ブロック"]
    end
    L2 -->|"❌ ブロック"| DENY(("🚫"))
    L2 --> L3
    subgraph L3["🔍 検知"]
        C["/review\n6観点レビュー"]
    end
    L3 --> SAFE["✅ 安全な\n変更"]
```

| レイヤー | 仕組み | 例 |
|---------|--------|-----|
| **認知** | CLAUDE.md ルール（HARD/SOFT/GUIDE） | 「main に push するな」 |
| **強制** | Pre-tool hooks（JSON deny = ブロック） | `guard-bash.sh` が `rm -rf` をブロック |
| **検知** | `/review` スキル（6観点） | PR でセキュリティ問題を検出 |

**deny リスト**（絶対に実行されない — settings.json でブロック）:
- `prisma db push`、force push

**guard ブロック**（hooks が JSON `permissionDecision: "deny"` でブロック）:
- `rm -rf`、`.env` 変更、保護ブランチへの push、本番DB操作

**HARD ルール**（Claude がユーザーに確認してから実行）:
- `git push`（feature ブランチ）、`gh pr create`、`gh pr merge`

**それ以外** — `Bash(*)` で自動承認。ダイアログなし。

### スキル: 14の再利用ワークフロー

| カテゴリ | スキル | 用途 |
|---------|--------|------|
| **レビュー** | `/review`, `/review-code`, `/review-test`, `/review-ops`, `/review-design`, `/review-spec` | 変更スコープに応じて動的に必要な観点だけ実行 |
| **ライフサイクル** | `/setup`, `/close-chat`, `/weekly-review`, `/news` | セッション・プロジェクト管理 |
| **ナレッジ** | `/record-decision`, `/inventory` | ADR記録、バージョン追跡 |
| **自動化** | `/auto-implement` | 実装→テスト→レビュー→PR を全自動 |

### 知識パイプライン: セッションが原則になるまで

```
セッション1: 「テストでDBモックを使うな」
  → feedback_testing.md に保存

セッション2: 「結合テストもリアルDB使って」
  → feedback_testing.md（2回目）

セッション3: 「ステージングDBで必ずテストしろ」
  → 3回目を検出 → thinking.md §1 に昇格

以降: Claude が原則として自動適用
```

### 自動モード: 寝てる間に PR ができる

```
あなた: 「設計OKだね。/auto-implement #10, #11, #12」
Claude: → 3つの Worktree を並列作成
        → 各 Issue を独立実装
        → /review を各PRに実行
        → push して PR を3つ作成
        → 知識還流 + バックログも自動蓄積
あなた: *朝に PR をレビュー・マージ*
```

完全無人実行（夜間・離席中）:
```bash
claude --dangerouslySkipPermissions \
  -p "/auto-implement #10, #11, #12"
```

**`/auto-implement` パイプライン:**

```mermaid
flowchart LR
    P0["Phase 0\n設計確定\nチェック"] --> P1["Phase 1\nWorktree\n作成"]
    P1 --> P2["Phase 2\n実装\n🔒 隔離"]
    P2 --> P3["Phase 3\n/review\n↻ 最大3回"]
    P3 --> P4["Phase 4\nテスト →\nPush → PR"]
    P4 --> P5["Phase 5\n知識\n蓄積"]
    P0 -..->|"未確定"| STOP(("🛑"))
    P3 -..->|"BLOCKER"| STOP
```

**朝起きて見るレポート:**

```
=== /auto-implement 完了レポート（並列3件） ===

[全体結果] 2件成功 ✅ / 1件停止 🛑

── Issue #10: ユーザー認証 ── ✅
  [PR] #43 → release/stg
  変更: 8ファイル（+342, -28）
  テスト: 156 passed / レビュー: OK（Ops WARN 1件 → 修正済み）
  知識還流: 1件 / バックログ: 2件

── Issue #11: メール通知テンプレ ── ✅
  [PR] #44 → release/stg
  変更: 4ファイル（+89, -12）
  テスト: 160 passed / レビュー: OK

── Issue #12: 管理画面ダッシュボード ── 🛑
  [停止Phase] Phase 3（レビュー）
  [停止理由] BLOCKER: N+1クエリ（lib/dashboard.ts L45）
  [再開方法] N+1 修正後、/auto-implement #12 で再実行

── 次のアクション ──
  → PR #43, #44 をレビュー・マージ
  → Issue #12 は対話モードで N+1 修正、または修正後に再実行
==========================================================
```

**自動でも人間が判断するもの:**
- PR の main へのマージ
- DB マイグレーション
- 本番デプロイ

高度な設定（cron、Slack連携）は [cron-setup-guide.md](docs/cron-setup-guide.md) を参照。

---

## アーキテクチャ

```
sidekick/
├── CLAUDE.md                    # ルール・設定（HARD/SOFT/GUIDE）
├── .claude/
│   ├── hooks/                   # 安全の強制層
│   │   ├── guard-bash.sh        # 9ガード（push, rm, prisma, env 等）
│   │   ├── guard-commit-message.sh
│   │   ├── guard-db-operation.sh
│   │   ├── guard-protected-branch-edit.sh
│   │   ├── prompt-reminder.sh
│   │   └── session-start.sh
│   ├── skills/                  # 14の再利用ワークフロー
│   │   ├── review/              # オーケストレーター + agents/ + references/
│   │   ├── auto-implement/      # 全自動パイプライン
│   │   ├── close-chat/          # セッション締め + 知識還流
│   │   └── ...
│   ├── rules/                   # 領域特化ガイドライン
│   │   ├── thinking.md          # オーナーの判断原則
│   │   ├── knowledge-map.md     # 知識の配置先マップ
│   │   └── ...
│   ├── templates/               # /setup が opt-in で配置するファイル
│   │   ├── MEMORY.md            # セッション記憶テンプレート
│   │   ├── CLAUDE.local.md      # 個人設定テンプレート
│   │   └── github/              # GitHub Issue テンプレート・ラベル定義
│   ├── docs/                    # 開発者リファレンス（毎セッション読み込まない）
│   │   └── skill-agent-design.md
│   └── settings.json            # 権限、hooks、deny リスト
├── docs/
│   ├── decisions/               # ADR（設計判断記録）
│   ├── cron-setup-guide.md      # 自動実行ガイド
│   └── playwright-setup-guide.md
└── .github/                     # sidekick リポ自身用（下流には伝播しない）
    ├── ISSUE_TEMPLATE/
    └── labels.yml
```

---

## 設定

`CLAUDE.md` 冒頭の `Project Configuration` で設定:

| 設定 | 説明 | デフォルト |
|------|------|----------|
| `PROJECT_NAME` | プロジェクト名 | `""` |
| `STG_ENABLED` | ステージング環境 | `false` |
| `ORM_TYPE` | `prisma` / `drizzle` / `none` | `none` |
| `LANGUAGE` | `typescript` / `python` | `typescript` |
| `NOTION_ENABLED` | 外部タスクDB連携 | `false` |
| `TEST_COMMAND` | テストコマンド | `""` |
| `BUILD_COMMAND` | ビルドコマンド | `""` |

### スケーリング: 個人 → チーム

sidekick は個人開発者でも小チームでも使える。「エンタープライズ版」は不要。

| 設定 | 個人 | チーム |
|------|------|--------|
| Worktree | 任意 | 必須（並行作業） |
| `/review` | セルフレビュー | チームレビューゲート |
| `PROTECTED_BRANCHES` | `main` | `main`, `release/stg` |
| MEMORY.md | 個人メモ | 共有コンテキスト |

---

## 設計思想

1. **安全が最優先**: ハードブロックは絶対に解除されない。autoモードでも、ユーザーの指示でも、巧妙な回避策でも。

2. **ブラックリスト方式**: 危険なものだけリスト化。残りは全自動。([ADR-0002](docs/decisions/0002-blacklist-execution-and-two-lanes.md))

3. **知識が複利で効く**: セッションの気づきが feedback → 原則 → 思考OS に育つ。使うほど賢くなる。

4. **固定費、PJ比例しない**: Claude Max サブスクリプション上で動く。API 従量課金なし。10 PJ でも $100/月。([ADR-0003](docs/decisions/0003-slack-cron-architecture.md))

5. **Git が Source of Truth**: 外部DB不要。MEMORY.md + ADR + GitHub Issues で完結。Notion はオプション。([ADR-0004](docs/decisions/0004-context-consolidation-claude-code-first.md))

---

## バージョン管理

sidekick は **git tag + GitHub Releases** でバージョン管理する。プロジェクトルートに VERSION ファイルは置かない。

各プロジェクトの `MEMORY.md` に取り込み済みバージョンを記録:
```markdown
<!-- sidekick_version: 0.3.0 -->
```
`/inventory` で最新の GitHub Release と比較し、更新を確認できる。

## ライセンス

MIT

<!-- sidekick_version: 0.3.0 -->
