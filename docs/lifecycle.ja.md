# ccs ライフサイクル地図

*ccs の全体を「閉じた輪の集合」として捉える地図* — 機能の山ではない。保守者向けに、**全機能・各機能が乗るライフサイクル輪・その輪が閉じているか（出力を次段が消費するか）/ 開いているか（段に道具が無い、または出力に消費者が無い）**を一望する。北極星: 使われない機能は無価値。機能は漏れなく無駄なく回る輪を成すべき。

EN: [lifecycle.md](./lifecycle.md) · 思想ダイジェスト: [design.ja.md](./design.ja.md) · 設計判断: [decisions/README.md](./decisions/README.md)

## 背骨（一本の筋）

- **北極星（ADR-0018）**: 下流開発者はハーネスを意識せず恩恵だけ感じる。既定で安全・組み立て不要・**手で打つのは3動詞だけ**（`/news` → 作業 → `/close-chat`、＋週次 `/weekly-inventory`）。他は全部勝手に発火する配管。
- **仕組み化 = 認知 → 強制 → 検知**。ルールだけでは守れないので、CLAUDE.md の HARD/SOFT/GUIDE ルール（`prompt-reminder.sh` が毎ターン再提示＝認知）を PreToolUse guard + `settings.json` deny list + git-native PII pre-commit hook（強制）で物理的に裏打ちし、すり抜けは `/review`（決定的 fitness + 公式 `/code-review` + REVIEW.md 規範・検知）が捕まえる。
- **知識複利（moat・ADR-0007/0016）**: feedback → auto-memory → `/close-chat` 還流フラグ → `/weekly-inventory` 昇格 → PJ brain → 個人 brain → OSS テンプレ → 翌セッション自動適用。AGENTS.md 的な instruction 共有では運べない判断層。

## 輪の一覧

| # | 輪 | 段の連鎖（各段の機能） | 閉？ |
|---|---|---|---|
| 1 | **Session**（日次・3動詞） | `session-start.sh`（ff-pull + Active Work/staleness/critical/brain を surface）→ `/news` → 作業（worktree + guard）→ `/review` → PR → `/close-chat` → 週次 `/weekly-inventory` → `/news` へ | ✅ |
| 2 | **知識複利** | feedback → auto-memory `feedback_*.md` → `/close-chat` 還流フラグ → `/weekly-inventory`（3件ルール）→ PJ brain → 個人 brain → OSS テンプレ → 翌セッション | ✅ |
| 3 | **Dev パイプライン** | `/discover`（調査 + Issue 作成可）→ `/record-decision`（ADR）→ `/auto-implement`（`gh issue view` → worktree → 実装+テスト → `/review` → PR）→ `/review` → PR | ✅ |
| 4 | **Release → Adopt** | `/release`（GitHub Release に severity マーカー）→ `/inventory`（下流: 版/severity 差検知）→ `session-start.sh` が critical flag を surface → `/adopt-sidekick-update`（バッチ適用・`SIDEKICK_VERSION` 更新・個人 brain は上書きしない） | ✅ |
| 5 | **強制 ×3**（認知→強制→検知） | worktree 規律（H9/H12 → `prompt-reminder` → `guard-bash`/`guard-protected-branch-edit` DENY）・PII（`pii-prevention` → `/review`/`/close-chat` scan → `githooks/pre-commit` block）・commit 本文（H15 → `guard-commit-message` block） | ✅ |
| 6 | **逆流**（下流 → 保守者） | GitHub Issue（`.github/ISSUE_TEMPLATE/`）→ `/inventory` Step 3（`gh issue list`）→ `/discover`/`/auto-implement` → `/release` | ✅（README では一方通行に見える＝doc gap・輪は切れてない） |
| 7 | **stack-pack アプリ構築**（opt-in Next.js） | `STACK_PACK=nextjs` → `ARCHITECTURE.md`（認知）→ `scaffold.js`（強制/生成）→ `fitness-functions`/`test:arch`（検知）→ `system-map`（可視化） | ⚠️ **開**（下記） |
| 8 | **上流ウォッチ**（Claude Code 公式 → ccs） | `news-upstream`（週次ウォッチ）→ gap 分析 → backlog → `/weekly-inventory` → ADR / skill / OSS テンプレ | ⚠️ **配布リポでは開**（下記） |

## 開いている輪（輪が閉じ切らない箇所）

- **7. stack-pack の再実行は `/review` ゲート依存で、完全自動配線ではない。** 背景 hook / PostToolUse / `.github/workflows` のどれも単独では `test:arch`/`system-map` を回さない（下流 PJ が自前 CI を配線）。ただしループ内では `/review`（ユーザー起動）が `STACK_PACK: nextjs` 時に fitness fast-gate と `system-map` drift nudge（canonical-counts `--drift`）を回し（v0.11.0）、硬層 adapter（route/authz/links/schema/indexes）は出荷済みで `fitness` と canonical な `route-enumerator.js` を共有する。残る開放点: 地図の**再生成**は on-demand（`/system-map`・意図的に自動再生成しない）、軟層 **enrich** は実行時 LLM 依存（機械化されていない）、`uncertainties`（golden-path 非準拠）は手動レポートとして届くだけで `fitness`/`ARCHITECTURE.md` に**還流しない**。**半分は設計**（下流が CI を持つ・地図はゲートでなく可視化物）— 正直な明記は README の stack-pack 節に置く。
- **8. 上流ウォッチは保守者のマシンでのみ回る。** `news-upstream` は意図的に**非配布**（`~/.claude/skills/` に退避・ADR-0017/0006）。リポ内 `/news` は*コードベース*の変化を見るもので軸が違う。配布物を読む人には上流→backlog→brain の流入が不可視。意図的だが、欠落段に見えないよう README に1行注記すべき。

## 保守者専用 vs 配布

| 面 | 状態 |
|---|---|
| `news-upstream`（上流ウォッチ） | 保守者専用 `~/.claude/skills/`（ADR-0017/0006）— 本リポに無し |
| `sync-oss` | 退役（ADR-0006 単一リポ統合） |
| OSS テンプレ還流 | 単一リポ化後は**同一リポ内編集**（cross-repo PR ではない） |
| 判断ログ Notion sync（ADR-0012） | opt-in・既定 off・書き専 export sink（設計上、閉じた輪ではない） |

## 機能インベントリ

> `claude-code-sidekick` main（2026-07-05・v0.12.0 以降）で実体確認。**配布コア skill 13本**（+ 次マイナーで撤去する deprecated `review-*` スタブ 5本）+ **opt-in stack-pack skill 1本**（`system-map`・Next.js）。

### Skills — session / lifecycle
| Skill | 何 | トリガ |
|---|---|---|
| `/setup` | 新規/オーバーレイ PJ 立ち上げ・個人 brain 初期化・ccs remote 登録・Next.js pack opt-in・`core.hooksPath` 設定 | user（一度） |
| `/news` | main を ff-pull + 前回 HEAD 以降の変更を分類要約 | user（動詞①） |
| `/inventory` | 横断棚卸し（Notion + `gh issue list` + Backlog）+ 版/severity チェック・critical flag 書き出し | user |
| `/close-chat` | セッション末の回収: backlog + 還流フラグ + PII/CHANGELOG チェック | user（動詞③）/ `/auto-implement` |
| `/weekly-inventory` | 圧縮: brain 健康度・MEMORY 整理・feedback 3件昇格・還流フラグ処理・drift | user（週次） |

### Skills — dev パイプライン & review
| Skill | 何 | トリガ |
|---|---|---|
| `/discover` | アイデア→要件: 調査 + ヒアリング + gap 分析 + タスク分解（Issue 作成可） | user |
| `/auto-implement` | 自律: 解析 → worktree → 実装+テスト → `/review` → PR → 回収 | user / 無人 |
| `/record-decision` | 採番 ADR 作成 + decisions index 更新 | user / `/close-chat` / `/discover` |
| `/tune` | read-only 4レーン PJ 健全性監査 → 人手ゲート修正（テスト削除はしない） | user |
| `/token-audit` | read-only 文脈経済監査: 常駐 footprint + 汚染/肥大/重複検知 + 公式 `rate_limits` 読取り | user |
| `/review` | アダプタ → 決定的 fitness → 公式 `/code-review`（REVIEW.md 規範）→ min() 総合判定 | user / `/auto-implement` |
| `/review-code`・`/review-test`・`/review-ops`・`/review-design`・`/review-spec` | 非推奨 → `/review` に統合（次リリースで撤去） | `/review` 経由 |

### Skills — release / adopt
| Skill | 何 | トリガ |
|---|---|---|
| `/release` | ccs リリース切り: severity 判定 + CHANGELOG bump + tag + GitHub Release マーカー | user（保守者） |
| `/adopt-sidekick-update` | 下流が release を取込: カテゴリ別バッチ適用・`SIDEKICK_VERSION` 更新・critical flag 解除 | user（下流） |

### Stack pack — Next.js（opt-in・`.claude/stack-packs/nextjs/`）
| 構成物 | 役割 |
|---|---|
| `ARCHITECTURE.md` | 規定 golden path: S1-S8 MUST / H1-H4・grep 検証・①公式/②主流/③ccs独自（認知） |
| `scaffold/` | `scaffold.js` が規約準拠の `posts` スライスをコピー・template は fitness fixture を**兼ねる**（強制/生成） |
| `fitness-functions/` | 依存ゼロ Node checker・各 MUST → grep assertion・`route-enumerator.js` = 正準カウント（検知） |
| `system-map`（skill） | 単一オフライン HTML 地図: 画面↔API↔DB↔権限↔遷移・硬層静的 + 軟層ドメイン subagent・自己検証 |

### 強制 — hooks / guards
| Hook | 何 | トリガ |
|---|---|---|
| `settings.json` deny list | `prisma db push`・`git push --force` を hard block | permission engine |
| `session-start.sh` | 7段の開始レポート（branch+ff-pull・未コミット・Active Work・worktree・staleness・critical flag・brain） | SessionStart |
| `prompt-reminder.sh` | 毎プロンプトに CRITICAL RULES を注入 | UserPromptSubmit |
| `guard-bash.sh` | 11 Bash guard（main で checkout・保護 push・`.env` 書込・`rm -rf`・`prisma db push`・migrate 警告・gh api 書込・pr merge・find 一括削除・executor 警告・STG PR 経路 H10/H11） | PreToolUse Bash |
| `guard-commit-message.sh` | 背景/対応/影響 を欠く commit を block（H15） | PreToolUse Bash |
| `guard-db-operation.sh` | `PRD_DB_PATTERN` への書込を DENY（ccs では dormant・下流で有効） | PreToolUse Bash |
| `guard-protected-branch-edit.sh` | `.env` DATABASE_URL 編集 + main での全編集を DENY（worktree 強制） | PreToolUse Edit/Write |
| `remind-worktree-memory.sh` | Worktree 新設を auto-memory Active Work へ記録するようリマインド（H13・認知層） | PostToolUse Bash |
| `budget-cycle-halt.sh` | Stop 境界の budget-gate（ADR-0024/0025): <60% 無出力 / 60–85% 助言のみ / >85% 1 回だけ wrap-up ターン・fail-open | Stop |
| `.claude/githooks/pre-commit` | staged 公開 blob の PII scan・commit 中断（`/setup` の `core.hooksPath` で有効化） | git pre-commit |

### 知識 & 判断
| 面 | 何 |
|---|---|
| auto-memory（`feedback`/`reference`/`project`/`user` + `MEMORY.md`） | Claude 記述の学習記録 + 索引 + Active Work/Backlog |
| `knowledge-map.md` | 背骨メタルール: 各知識型の格納先 + 昇格/圧縮ルール |
| brain（2層: 個人 + PJ + OSS テンプレ） | 判断軸・feedback が上方昇格・OSS 還流（同一リポ） |
| ADR（`docs/decisions/` + 索引） | 設計判断台帳（なぜ）・0011 予約・0017 不在（保守者専用） |

## 掃除済み / ガード済み cruft（2026-06）

- 死んでいた `.husky/pre-commit` + `.husky/pre-push` を削除（`core.hooksPath` 経路外・`package.json`/lint-staged 無し＝本物の `.claude/githooks/pre-commit` と矛盾する囮）。
- `.gitignore` で旧 top-level `.claude/skills/system-map/`（Spring/Vue 時代の port 残骸・固有名詞含む）を誤コミット防止にガード。正規版は `.claude/stack-packs/nextjs/skills/system-map/`。
