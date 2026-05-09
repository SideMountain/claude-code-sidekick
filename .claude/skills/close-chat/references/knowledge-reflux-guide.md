# 知識還流チェックガイド

/close-chat Step 2.5 で使用する分類基準と記録ルール。

## 分類基準

| 分類 | 基準 | 行き先 |
|------|------|--------|
| OSS 還流候補 | 業界共通の判断軸（誰が使ってもベースとして有効） → Yes | sidekick OSS テンプレート（`brain/thinking.md`）への手動 PR |
| 個人 brain 昇格 | 複数 PJ 横断の判断軸（同じ自分が別 PJ でも同じ判断） → Yes | `~/.claude/brain/thinking.md` 昇格候補 |
| PJ 固有 | この PJ ドメイン・成熟度・チーム文化に依存 | `<PJ>/.claude/brain/thinking.md` 昇格 |

判定の質問: **「全 PJ で適用したい判断軸か?」** YES → 個人 brain、NO → PJ brain。個人 brain の中で「業界共通として外部公開する価値があるか?」YES → OSS 還流候補。迷った場合は PJ brain から始め、3 件ルールで個人 brain / OSS 還流候補に昇格させる。

## 抽出対象

- ユーザーが明示的に示した設計思想・原則
- ユーザーが提案を却下した理由（却下理由はパターン化しやすい）
- ユーザーが非自明な方針を承認した理由（「それでいい」の裏にある判断軸）
- セッション中に発見された新しいパターンや落とし穴

## 抽出しないもの

- 既に feedback_*.md や brain（PJ brain / 個人 brain / OSS テンプレート）に記録済みのもの
- 単なるタスクの進捗（Step 2 で扱う）
- セッション固有の一時的な判断

## 記録アクション

| 分類 | 記録先 | 備考 |
|------|--------|------|
| OSS 還流候補 | feedback_*.md + MEMORY.md Backlog に `[OSS 還流候補]` | 実際の還流は棚卸し時、sidekick リポへの手動 PR |
| 個人 brain 昇格 | feedback_*.md + MEMORY.md Backlog に `[個人 brain 昇格]` | 個人 brain への昇格は棚卸し時 |
| PJ 固有 | feedback_*.md + MEMORY.md Backlog に `[PJ 固有]` | PJ brain への昇格は棚卸し時、必要なら ADR も |

**重要: 即座に brain ファイルを更新しない。** フラグを立てるだけ。統合は棚卸し時にまとめてやる。
