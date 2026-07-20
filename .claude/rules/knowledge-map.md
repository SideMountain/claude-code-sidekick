# 知識の格納マップ

知識が生まれたとき「どこに置くか」を判断するメタルール。
「同じルールを5箇所に薄く置くより、正しいレイヤーに1つ強く置く方が効く」が原則。

## 格納レイヤーと役割

| レイヤー | 役割 | 書く人 | Git管理 | ロード対象 | 寿命 |
|---|---|---|---|---|---|
| `hooks/permissions` | 機械的に止める（enforcement） | 人間 + Claude | される | — | 長い |
| `CLAUDE.md` | プロジェクトルール（what to do） | 人間 + Claude（合意の上） | される | ✅ | 長い |
| `CLAUDE.local.md` | 個人設定（personal preferences） | 個人 | されない | ✅ | 長い |
| `~/.claude/brain/thinking.md` | 個人 brain — 個人の判断軸（複数 PJ 横断、how to think） | 個人 + Claude（feedback 昇格） | されない | ✅ | 長い |
| `<PJ>/.claude/brain/thinking.md` | PJ 固有 brain — PJ 固有の判断軸（how to think、PJ 差分） | 人間 + Claude（合意の上） | される | ✅ | 長い |
| `brain/thinking.md`（sidekick リポ内） | OSS テンプレート — 個人 brain の初期テンプレート素材（配布物） | Claude（合意の上、OSS 還流で更新） | される | ❌ | 長い |
| `rules/*.md`（brain 以外） | 領域特化ルール（what to do, scoped） | 人間 + Claude（合意の上） | される | ✅（path-scoped） | 長い |
| `skills/` | 繰り返し手順（how to do） | Claude（合意の上） | される | 呼び出し時 | 中〜長い |
| `~/.claude/skills/`（user-level スキル） | 職能ナレッジ — プロジェクト非依存の役割別判断軸・メソッド（how to think, role-scoped） | 個人 + Claude（合意の上） | されない（実体は個人のナレッジリポで管理し、コピー配布） | description 常駐 + 呼び出し時 | 長い |
| `agents/` | 専門実行主体の定義（who does it） | Claude（合意の上） | される | 呼び出し時 | 長い |
| `docs/decisions/` (ADR) | 設計判断記録（why we decided） | Claude（合意の上） | される | — | 永続 |
| `agent-memory/` | エージェントの学習記録（PJスコープ共有） | Agent（自動） | される | — | 可変（棚卸しで整理） |
| `agent-memory-local/` | エージェントの学習記録（個人ローカル） | Agent（自動） | されない | — | 可変 |
| `skills/*/.data/` | スキル永続データ（分析履歴・キャッシュ） | Claude（自動） | されない | — | 可変 |
| auto-memory `feedback_*.md` | 行動修正の経緯記録（what not to do） | Claude（自動） | されない | — | 中（昇格 or 統合で整理） |
| auto-memory `reference_*.md` | 外部システム・設定へのポインタ | Claude（自動） | されない | — | 長い |
| auto-memory `project_*.md` | 進行中の作業・ゴール・マイルストーン | Claude（自動） | されない | — | 中（作業完了で整理） |
| auto-memory `user_*.md` | ユーザーの役割・好み・知識 | Claude（自動） | されない | — | 長い |
| auto-memory `MEMORY.md` | 索引 + Active Work + Backlog | Claude（自動） | されない | ✅ | 可変（棚卸しで整理） |

brain は 2 層構造（ADR-0016）。OSS テンプレート（`brain/thinking.md`）は配布素材で、`/setup` で個人 brain 不在時のみコピーされる（既存個人 brain は上書き禁止）。

user-level スキル（`~/.claude/skills/`）は Claude Code の標準機構で、置いたスキルは全プロジェクトのセッションにロードされる。役割別の職能ナレッジ（経営・プロダクト・技術投資などの判断軸）をプロジェクト非依存で使い回す場合はこの層に置く。推奨運用: 実体は専用の個人ナレッジリポで一元管理し、配布スクリプト（rsync 等）で `~/.claude/skills/` へコピー配布する — 実体一元でドリフトを防ぎ、検知は配布スクリプトの差分チェックで行う。個人 brain との使い分けは「思考スタイル（常駐で全出力に効かせたい）→ brain / 役割の判断手順・チェックリスト（該当場面だけ呼び出したい）→ user-level スキル」。

## 判断フロー

知識が生まれたとき、以下の順で置き場を決める。

```
知識が生まれた
  │
  ├── 機械的に止めるべきか？
  │     → Yes → hooks/permissions（最も強い。判断不要で止まる）
  │
  ├── 判断原則・思考スタイルか？
  │     ├── 全 PJ で適用したい（複数 PJ 横断） → 個人 brain（~/.claude/brain/thinking.md）
  │     └── PJ 固有（PJ ドメイン依存）         → PJ brain（<PJ>/.claude/brain/thinking.md）
  │     ※ 迷ったら PJ brain から始め、3 件ルールで個人 brain に昇格させる
  │
  ├── 役割（経営・プロダクト・技術投資等）の職能ナレッジで、プロジェクト非依存か？
  │     → Yes → user-level スキル（`~/.claude/skills/`。実体は個人のナレッジリポに置き、コピー配布で全プロジェクトへ）
  │     ※ 個人の思考スタイルは個人 brain、プロジェクト固有の事実（ペルソナ実体・価格等）は各プロジェクトの docs に置く
  │
  ├── プロジェクト全体のルール（規約）か？
  │     ├── 全セクションに適用 → CLAUDE.md
  │     └── 特定領域のみ → rules/*.md
  │
  ├── 繰り返し実行する手順か？
  │     → Yes → skills/
  │     ⚠ スキル新規作成時は `.claude/docs/skill-agent-design.md` を必ず Read してから着手する
  │
  ├── 専門的な実行主体の定義か？（ツール権限・モデル・事前知識の固定）
  │     → Yes → agents/（.claude/docs/skill-agent-design.md §4 の判断基準を参照）
  │
  ├── 設計判断の「なぜ」か？
  │     → Yes → ADR（docs/decisions/）
  │
  ├── Claudeの行動修正か？
  │     → Yes → auto-memory の `feedback_*.md` + `MEMORY.md` 索引
  │     → 3回以上同趣旨が溜まったら → brain（PJ brain / 個人 brain）に昇格
  │
  └── 上記いずれにも該当しない補足情報
        → auto-memory の `MEMORY.md`
```

## 知識の種類別ガイド

| 知識の種類 | 例 | 置き場 |
|---|---|---|
| ユーザーの修正指示 | 「dry-run省略するな」 | auto-memory `feedback_*.md` |
| ユーザーの承認 | 「A案でいい」 | ADR（設計判断の場合）/ 消える（軽微な場合） |
| 設計思想・原則（業界共通） | 「意図のないコードは書くな」 | OSS テンプレート（`brain/thinking.md`、配布物として PR） |
| 設計思想・原則（個人横断） | 「確証 95% 未満は断定しない」 | 個人 brain（`~/.claude/brain/thinking.md`） |
| 設計思想・原則（PJ 固有） | 「拡張ファースト」（sidekick 特有） | PJ brain（`<PJ>/.claude/brain/thinking.md`） |
| 職能の判断軸（役割別・プロジェクト非依存） | 「技術的負債の優先順位の判断式」「価格設定の判断軸」 | user-level スキル（`~/.claude/skills/`・個人のナレッジリポで管理） |
| 事故・障害の教訓 | 「マージコマンドをテスト目的で実行しない」 | auto-memory `feedback_*.md` or CLAUDE.md Lessons Learned |
| 実装パターン | フレームワーク固有の落とし穴等 | auto-memory `reference_*.md` |
| 運用手順 | 「本番DBはコマンド単位で接続文字列を渡す」 | CLAUDE.md + rules/*.md |
| UIルール | 「ブラウザネイティブダイアログを使わない」 | auto-memory `feedback_*.md` + rules/ |
| 外部連携の情報 | 「Notion タスクDB の ID」 | auto-memory `reference_*.md` |
| 一時的な作業状態 | 「今このタスクをやっている」 | auto-memory `MEMORY.md` の Active Work |
| 積み残しタスク（個人・working・未成形） | 「次回これをやる」 | auto-memory `MEMORY.md` の Backlog |
| 作業単位（チーム・機能改善・bug・他人が拾える） | 「この機能を追加」「このバグを直す」 | GitHub Issue（intake routing・ADR-0022・[task-management.md](task-management.md)） |
| スキルの分析履歴 | レビュー傾向、scout 結果 | skills/*/.data/ |
| スキル・エージェントの設計判断 | 「隔離する/しない」「エージェント定義を作る」 | .claude/docs/skill-agent-design.md |

## 昇格と圧縮のルール

> **昇格・還流の判定 rubric（R5 同趣旨 / R6 昇格 / R7 還流 3 分類）と few-shot は `.claude/docs/knowledge-reflux.md`（単一ソース）を参照する。** 本節はレイヤー構造（昇格パス・圧縮）だけを持つ。

### 昇格（feedback → PJ brain → 個人 brain → OSS テンプレート還流）

- 同趣旨の feedback が3回以上溜まったら、原則への昇格を検討する（同趣旨判定 = doc R5・昇格判定 = doc R6）
  - **例外（致命クラス）**: `.claude/docs/knowledge-reflux.md` R6 の閉集合 `{ データ喪失, 本番影響, セキュリティ／ガード無効化, 不可逆 git 事故 }` に該当する教訓は N=1（単発観測）でも記録・昇格してよい。3 件ルールは「失っても致命的でない知見」の蓄積閾値であり、致命クラスには適用しない
- 昇格パス:
  - PJ 内同類 3 件 → PJ brain（`<PJ>/.claude/brain/thinking.md`）に昇格
  - 別 PJ で同類観測 → 個人 brain（`~/.claude/brain/thinking.md`）に昇格
  - 業界共通と判明 → OSS テンプレート（sidekick リポ `brain/thinking.md`）への手動 PR で還流
- 昇格後も feedback ファイルは経緯記録として残す（MEMORY.md 索引に「昇格済み」を明記）
- `/weekly-inventory` Step 3 で定期的に昇格候補を検出する

### 圧縮（統合・削除）

- 同趣旨の feedback は統合する（1つにまとめ、他はアーカイブ）
- 完了済みバックログは定期的に削除する
- brain ファイルが 200 行を超えたら圧縮を検討する:
  - 具体的すぎる原則は rules/ への降格を検討
  - 重複する原則は統合する
  - 上位層から下位層への適切な移動（例: 個人 brain から PJ brain へ、PJ 固有と判明したもの）
- `/weekly-inventory` で定期実行

### 知識還流（PJ → 個人 → OSS テンプレート）

- `/close-chat` Step 2.5 でフラグを立て、`/weekly-inventory` Step 4 でまとめて処理する（即時反映しない）
- 還流タグの分類・記録アクションの詳細と正 = `.claude/docs/knowledge-reflux.md`（R7・記録アクション節）

## 書かないもの（どこにも置かない）

- コードから直接読み取れるパターン・構造（コードが正）
- git log / git blame で分かる変更履歴
- 既にCLAUDE.mdに書いてあること（重複禁止）
- セッション固有の一時情報（今の会話の文脈等）
- 未検証の推測や仮説
