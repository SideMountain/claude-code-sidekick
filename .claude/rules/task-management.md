# タスク管理 — intake routing（Layer 0）+ 外部DB連携（Layer 2）

> **標準構成（Layer 0）**: sidekick は auto-memory Backlog + GitHub Issues だけで完結する（下記 intake routing）。
> Notion 等の外部DB連携は、非エンジニアとのタスク共有が必要な場合の Layer 2 オプション拡張。

## intake routing（Layer 0・標準・ADR-0022）

作業項目を「どこに置くか」を **audience × 永続性 ×「他人が拾えるか」**で振り分ける。標準は **backlog + GitHub Issues の二トラック**（Notion は Layer 2 の任意拡張）。

| 行き先 | 何を置くか | 性質 |
|---|---|---|
| **auto-memory `BACKLOG.md`**（既定・最軽） | 個人の次セッション用メモ・working context・未成形の検討残 | local・git 非追跡・**常駐しない**・`/weekly-inventory` が圧縮 |
| **GitHub Issue** | チームの機能改善・bug・**他人が拾える具体的作業単位**・可視化したいもの | repo native・追跡可・逆流ループ（Issue → `/inventory` → `/discover`/`/auto-implement` → `/release`）に乗る |
| Notion（Layer 2・任意） | 非エンジニア横断のタスク共有 | `NOTION_ENABLED=true` 時のみ（下記） |

**判定の一言**: 「他人が拾えるか / チームに見せたいか / 具体的な作業単位か」→ YES なら **Issue**、NO なら **backlog（既定）**。

**backlog は `MEMORY.md` と別ファイルにする（ADR-0035）**: `MEMORY.md` は毎セッション自動ロードされる。
積み残しをそこに置くと**そのセッションで使わない情報が常駐コストを食う**。実運用では backlog が
`MEMORY.md` 全体の 4 割に達し、読み取り上限に到達しかけた。`BACKLOG.md` に分けておけば、
backlog がどれだけ伸びても `MEMORY.md` は伸びない。消費側が必要なときに読む。

**ルール（軽さ優先）:**
- ルーティングは **heuristic（提案）で強制ゲートにしない**。迷ったら軽い backlog が既定。
- ⚠️ **`［Issue推奨］`と書いたまま放置しない。** それは「判定は済んでいるのに行動していない」状態で、
  backlog が Issue の代替物として溜まっていく。判定したら**その場で起票する**。
  `/weekly-inventory` はこのタグの滞留を**棚卸しの先頭に強制表示**する。
- **「これ Issue にして」を摩擦ゼロの一級アクションに** — `/discover` のフルフローを通さず単発 `gh issue create`（`.github/ISSUE_TEMPLATE/` + ラベル）。
- **1 アイテム＝1 ホーム（重複禁止）**。backlog が具体化したら **Issue へ昇格 → backlog から削除（Issue# 参照）**。feedback→brain と同じ昇格ラダー。
- 消費側: `/inventory` が backlog + Issues（+ Notion）を横断照合し、`/close-chat` が起票先を提案する。

---

## 外部DB連携（Layer 2・オプション）+ 判断ログ同期

Notion 等の外部タスク管理DB連携（`NOTION_ENABLED=true`）と判断ログ同期（`NOTION_JUDGMENT_SYNC=true`）の詳細プロトコルは `.claude/docs/task-db-layer2.md`（遅延ロード・**常駐しない**）を参照する。

既定（両フラグ false）の PJ はこのレイヤー全体をスキップしてよい — sidekick は auto-memory Backlog + GitHub Issues だけで完結する（Layer 0）。
