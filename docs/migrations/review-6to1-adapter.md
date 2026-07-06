# 移行ガイド: review 6 スキル → /review アダプタ + REVIEW.md

> 対象: ccs を取り込んでいる下流 PJ。
> 背景の設計判断: ADR-0027（公式スキル採用とラップ配布）。

## 何が変わったか

review 系 6 スキル（`/review` + `/review-code` `/review-test` `/review-ops` `/review-design` `/review-spec`）が **1 つのアダプタ**に統合された。

| 旧 | 新 |
|---|---|
| `/review` が 5 観点を並列 fan-out | `/review` が **決定的 fitness → 公式 `/code-review`（REVIEW.md 注入）→ min() 総合判定** |
| 観点別スキル 5 本が各自レビュー | **REVIEW.md** に PJ 規範を集約（HARD照合・ADR整合・破壊的変更・a11y・hook 教訓） |
| 破壊的キーワード検出が 4 箇所に prose 重複 | `review-fitness.sh` に 1 本化（+ a11y・空 catch 検出も） |

## 前提

- **公式 `/code-review` が使えること**（Claude Code の対応バージョン）。ultra を使う場合は `code-review-ultra` の下限を feature gate（`hook-helpers.sh`）が判定する。
- 公式が不在でも `/review` は REVIEW.md 準拠の手動レビューに fallback する（silent 破綻しない・ADR-0027 決定 3）。

## 下流 PJ の移行手順

1. **取り込み**: `/adopt-sidekick-update` でこのリリースを取り込む。以下が入る:
   - `REVIEW.md`（リポルート）
   - `.claude/skills/review/`（アダプタ SKILL.md + `scripts/review-fitness.sh` + `references/`）
   - 旧 `.claude/skills/review-*` スタブは撤去済み（下流に残っていれば取り込みで削除される）
2. **REVIEW.md の調整**: `/setup` を再実行するか、`REVIEW.md` の PJ 固有部分を手で調整する。該当しない条件ブロック（§1e design-system / §1f STACK_PACK）は削除してよい。仕様書の在り処（Notion 等）を §1b に反映する。
3. **参照の更新**: `/review-code` 等を直接指名している独自 rules / CLAUDE.md があれば `/review` に置換する。
4. **動作確認**: 変更のあるブランチで `/review` を実行し、fitness → `/code-review` → min() 判定が出ることを確認する。

## 撤去状況

- `/review-*` スタブは撤去済み。`/review` に一本化された。下流 PJ にスタブが残っている場合、このリリースの取り込みで削除される。
- スタブを直接指名していた独自 rules / CLAUDE.md は `/review` へ置換する（上記「下流 PJ の移行手順」3）。

## FAQ

- **観点別の深掘り（テスト網羅性・セキュリティ等）は失われないか?** — 一般観点は公式 `/code-review` の effort（high / ultra）でカバーし、PJ 固有観点は REVIEW.md §1 が担う。セキュリティ深掘りは `/security-review` に委譲する。
- **REVIEW.md は誰が読むのか?** — 公式 `/code-review` が最優先の観点として読み、`/review` アダプタも二重適用の形で読む（注入が効かないバージョンでも規範が生きる）。
