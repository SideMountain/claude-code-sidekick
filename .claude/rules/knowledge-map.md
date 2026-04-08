# 知識の格納マップ

知識が生まれたとき「どこに置くか」を判断するメタルール。
「同じルールを5箇所に薄く置くより、正しいレイヤーに1つ強く置く方が効く」が原則。

## 格納レイヤーと役割

| レイヤー | 役割 | 書く人 | Git管理 | 寿命 |
|---|---|---|---|---|
| `hooks/permissions` | 機械的に止める（enforcement） | 人間 + Claude | される | 長い |
| `CLAUDE.md` | プロジェクトルール（what to do） | 人間 + Claude（合意の上） | される | 長い |
| `CLAUDE.local.md` | 個人設定（personal preferences） | 個人 | されない | 長い |
| `rules/*.md` | 領域特化ルール（what to do, scoped） | 人間 + Claude（合意の上） | される | 長い |
| `skills/` | 繰り返し手順（how to do） | Claude（合意の上） | される | 中〜長い |
| `agents/` | 専門実行主体の定義（who does it） | Claude（合意の上） | される | 長い |
| `docs/decisions/` (ADR) | 設計判断記録（why we decided） | Claude（合意の上） | される | 永続 |
| `agent-memory/` | エージェントの学習記録（PJスコープ共有） | Agent（自動） | される | 可変（棚卸しで整理） |
| `agent-memory-local/` | エージェントの学習記録（個人ローカル） | Agent（自動） | されない | 可変 |
| `skills/*/.data/` | スキル永続データ（分析履歴・キャッシュ） | Claude（自動） | されない | 可変 |
| `feedback_*.md` | 行動修正の経緯記録（what not to do） | Claude（自動） | されない | 中（昇格 or 統合で整理） |
| `MEMORY.md` | 索引 + 状態管理 + バックログ | Claude（自動） | されない | 可変（棚卸しで整理） |

## 判断フロー

知識が生まれたとき、以下の順で置き場を決める。

```
知識が生まれた
  │
  ├── 機械的に止めるべきか？
  │     → Yes → hooks/permissions（最も強い。判断不要で止まる）
  │
  ├── プロジェクト全体のルールか？
  │     ├── 全セクションに適用 → CLAUDE.md
  │     └── 特定領域のみ → rules/*.md
  │
  ├── 繰り返し実行する手順か？
  │     → Yes → skills/
  │
  ├── 専門的な実行主体の定義か？（ツール権限・モデル・事前知識の固定）
  │     → Yes → agents/（rules/skill-agent-design.md §4 の判断基準を参照）
  │
  ├── 設計判断の「なぜ」か？
  │     → Yes → ADR（docs/decisions/）
  │
  ├── Claudeの行動修正か？
  │     → Yes → feedback_*.md + MEMORY.md索引
  │     → 3回以上同趣旨が溜まったら → thinking.md に昇格
  │
  └── 上記いずれにも該当しない補足情報
        → MEMORY.md
```

## 知識の種類別ガイド

| 知識の種類 | 例 | 置き場 |
|---|---|---|
| ユーザーの修正指示 | 「dry-run省略するな」 | feedback_*.md |
| ユーザーの承認 | 「A案でいい」 | ADR（設計判断の場合）/ 消える（軽微な場合） |
| 設計思想・原則 | 「意図のないコードは書くな」 | thinking.md §1 |
| 事故・障害の教訓 | 「マージコマンドをテスト目的で実行しない」 | MEMORY.md Lessons |
| 実装パターン | フレームワーク固有の落とし穴等 | MEMORY.md Lessons |
| 運用手順 | 「本番DBはコマンド単位で接続文字列を渡す」 | CLAUDE.md + rules/*.md |
| UIルール | 「ブラウザネイティブダイアログを使わない」 | feedback + rules/ |
| 外部連携の情報 | 「Notion タスクDB の ID」 | MEMORY.md（参照情報） |
| 一時的な作業状態 | 「今このタスクをやっている」 | MEMORY.md Active Work |
| 積み残しタスク | 「次回これをやる」 | MEMORY.md Backlog |
| スキルの分析履歴 | レビュー傾向、scout 結果 | skills/*/.data/ |
| スキル・エージェントの設計判断 | 「隔離する/しない」「エージェント定義を作る」 | rules/skill-agent-design.md |

## 昇格と圧縮のルール

### 昇格（feedback → thinking.md / CLAUDE.md）

- 同趣旨のfeedbackが3回以上溜まったら、原則への昇格を検討する
- 昇格後もfeedbackファイルは経緯記録として残す（MEMORY.md索引に「昇格済み」を明記）
- `/weekly-review` Step 3 で定期的に昇格候補を検出する

### 圧縮（統合・削除）

- 同趣旨のfeedbackは統合する（1つにまとめ、他はアーカイブ）
- 完了済みバックログは定期的に削除する
- `/weekly-review` で定期実行

### 知識還流（プロジェクト → ベーステンプレ / 思考OS）

- `/close-chat` Step 2.5 でフラグを立てる
- `/weekly-review` Step 4 でフラグをまとめて処理する
- 即座に反映しない。蓄積→パターン検出→統合の順

## 書かないもの（どこにも置かない）

- コードから直接読み取れるパターン・構造（コードが正）
- git log / git blame で分かる変更履歴
- 既にCLAUDE.mdに書いてあること（重複禁止）
- セッション固有の一時情報（今の会話の文脈等）
- 未検証の推測や仮説