# ADR-0008: project-root MEMORY.md を廃止し auto-memory に一本化

## ステータス

採用（2026-04-18）

## 背景

sidekick はプロジェクトルートに `/MEMORY.md`（gitignored）を配置して、Active Work / Backlog / Memory Index を運用する設計だった。

一方で、Claude Code 本体には 2024 年以降 **auto-memory** システムが第一級の機能として実装されている:

- `~/.claude/projects/<project-slug>/memory/` に Claude が自動的に記録
- types: `user` / `feedback` / `project` / `reference` の個別ファイル
- `MEMORY.md` が索引として生成される
- システムプロンプトで明示的にサポート

実下流 PJ を調査した結果、**auto-memory MEMORY.md が Active Work / Backlog の実運用場所**になっており、project-root MEMORY.md は静的情報（Project Overview / Milestones 等）のみに使われていた。

この 2系統並列は以下の問題を起こしていた:

1. **役割の曖昧さ**: どちらに何を書くかが不明確（close-chat SKILL.md も「MEMORY.md」とだけ記載、path 未明示）
2. **hook の矛盾**: `session-start.sh` は auto-memory MEMORY.md を読むが、`/close-chat` の説明では project-root 想定とも読める
3. **Claude Code 標準との乖離**: Claude Code 公式は auto-memory を推し、project-root MEMORY.md は sidekick 固有の pre-auto-memory 時代の遺物
4. **新規ユーザー体験の低下**: Claude Code 流儀を知る人が sidekick に来ると、project-root MEMORY.md の存在に戸惑う

## 検討内容

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| **A: auto-memory に一本化（採用）** | Claude Code 標準準拠。1系統で明確。保守性 | 既存下流 PJ に移行ガイド必要。sidekick_version の置き場移動 |
| B: 2系統の役割を明確化して維持 | 既存移行ゼロ | 「どちらに書くか」の曖昧さが永続。レガシーの温存 |
| C: project-root MEMORY.md に一本化 | auto-memory を無視する | Claude Code 標準から逆行。将来の新機能に乗れない |

## 決定

**A: auto-memory に一本化。** project-root `/MEMORY.md` とそのテンプレートを廃止する。

### 影響する変更

1. `.claude/templates/MEMORY.md` を削除
2. `/setup` の MEMORY.md 配置ロジックを削除
3. `.gitignore` から `/MEMORY.md` エントリを削除
4. `/inventory` の `sidekick_version` 読み先を MEMORY.md → `CLAUDE.md` の `SIDEKICK_VERSION` へ
5. `CLAUDE.md` Project Configuration に `SIDEKICK_VERSION` を追加
6. `/close-chat` の MEMORY.md 参照を auto-memory と明示
7. `rules/documentation.md` / `rules/knowledge-map.md` を auto-memory 前提に書き換え
8. `CLAUDE.md` H13 / ゲート3 を auto-memory 前提に更新
9. README.md / README.ja.md のバージョン管理セクションを更新
10. 下流 PJ 向け移行ガイドを `docs/migrations/memory-md-to-auto-memory.md` に配置

### `SIDEKICK_VERSION` の置き場所決定

`CLAUDE.local.md`（project-root gitignored）に配置する案は却下した。技術的理由:

- `SIDEKICK_VERSION` は本来チーム共有情報（同じプロジェクトは同じバージョンを使う）
- `CLAUDE.local.md` 置きだと個人ごとに異なる値を持ちうる（不整合の温床）
- CLAUDE.md 冒頭の Project Configuration には既に類似の設定値（`PROJECT_NAME`, `STG_ENABLED` 等）が並んでいる

→ **`CLAUDE.md` の Project Configuration に `SIDEKICK_VERSION` を追加**する。

## 理由

1. **Claude Code 標準準拠**: Claude Code が第一級の機能として auto-memory を提供している以上、それを使うのが自然
2. **DRY の徹底**: 2系統の並列は書き手と読み手の両方を混乱させる。1系統で明確化する
3. **システムプロンプト整合**: Claude Code のシステムプロンプトで示される memory 運用方法と sidekick の運用が一致する
4. **新規ユーザー体験の改善**: Claude Code 流儀を知っている人がそのまま sidekick を使える
5. **sidekick_version の CLAUDE.md 配置**: チーム共有が本来の意図なので git 管理下へ戻す（ローカル専用だった設計ミスの修正）

## 影響

### 既存下流 PJ への影響

- `.claude/templates/MEMORY.md` の配布が停止される → 新規 `/setup` は MEMORY.md を配置しない
- 既に project-root MEMORY.md を持つ PJ は、内容を以下に移管:
  - `Active Work` / `Backlog` → auto-memory MEMORY.md へ
  - `Project Overview` / `Milestones` → CLAUDE.md の新セクションまたは `docs/` 配下へ
  - `<!-- sidekick_version -->` → CLAUDE.md の `SIDEKICK_VERSION` へ
- 詳細な移行手順は `docs/migrations/memory-md-to-auto-memory.md` 参照

### sidekick 本体への影響

- sidekick 本体は project-root MEMORY.md を持たない（既に存在しない状態）
- auto-memory MEMORY.md を新規作成し、Active Work + Backlog を運用する
- Claude Code 標準の types（user/feedback/project/reference）が個別ファイルとして生成される

### 関連 ADR

- ADR-0004: Git を Source of Truth とする方針 — auto-memory は個人ローカルだが、「auto-memory は Claude Code が自動管理する補助領域」と位置づける
- ADR-0005: 下流統合設計原則「sidekick が直接配置しない」— auto-memory は Claude Code 自動管理なので射程外

## 参考

- Claude Code auto-memory システム（`~/.claude/projects/<slug>/memory/`）
- 実下流 PJ の運用実態（2系統並列からの気づき）
