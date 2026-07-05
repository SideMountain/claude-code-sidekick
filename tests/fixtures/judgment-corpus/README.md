# 凍結判定 corpus — 判定一致率の恒久基準器

モデル世代交代後もハーネスの判定品質を計測し続けるための、**凍結されたリファレンス判定集**（ADR-0028 決定2）。
`docs/plans/ccs-model-independence.md` §5① の判定一致率 A/B は、本 corpus を基準に実施する。

## 構造

| ディレクトリ | 内容 | 参照条件 |
|---|---|---|
| `cases/` | ケース入力 + 質問のみ | 被測定モデルに与えてよい |
| `expected/` | 凍結判定（verdict + must_find + 根拠） | **被測定モデルに絶対に見せない**（採点者のみ参照） |

| カテゴリ | 測るもの | 件数 | verdict 形式 |
|---|---|---|---|
| REV | レビュー総合判定（min()） | 5 | `verdict: 1\|2\|3` |
| HS | 難所判定（R2 閉集合の入口） | 4 | `hard_spot: YES\|NO` |
| REL | release 温度感（R10） | 3 | `severity: Critical\|Enhancement\|Standard` |
| KRF | 知識還流（R5/R6/R7） | 3 | ケースごと（classification / promote / same_gist） |
| GATE | 無人実行の入口（R1） | 2 | `decision: GO\|NO-GO` |
| DES | 設計判断の裁定（§8 難所 cat1） | 4 | `decision: A\|B\|C` |
| RC | root-cause 分析（§8 難所 cat2） | 3 | `root_cause: C1..C4` |
| CON | 矛盾裁定（§8 難所 cat3） | 3 | `resolution: R1\|R2\|R3` |

計 **27 件**。HS が「難所か否か」の入口判定であるのに対し、DES/RC/CON は「難所と判定した後、実際にどう裁定するか」を測る（設計は [corpus-expansion-v2-plan](../../../docs/plans/corpus-expansion-v2-plan.md)）。DES/RC/CON は「判断原則（brain §1）・rules に照らせば一意に決まる」題材のみ収録する（複数正解の題材は凍結の意味が消えるため不採用）。

## 凍結ルール（append-only）

- `expected/` の判定は **claude-fable-5（Mythos-class）が確定**したもの（REV/HS/REL/KRF/GATE = 2026-07-04、DES/RC/CON = 2026-07-05。各ファイルヘッダに凍結日を記載）。**別モデルでの再生成・上書きは禁止**（基準器の意味が消える）
- ケース追加は新 ID の追記のみ。既存ケースの入力・判定の変更は禁止
- 参照先 rubric（REVIEW.md / rubrics R1-R10 / knowledge-reflux.md / context-economy §8）が改訂され、ケースの前提が崩れた場合のみ「retired: 理由」を expected 側に付記して測定対象から外す（削除はしない）

## held-out 分割（few-shot 蒸留に使わない測定専用群）

- `expected/` の各ケースに `holdout: true|false` を付す。**holdout=true のケースは REVIEW.md / rubrics 等の few-shot exemplar に採用しない**（蒸留に混ぜると「教えた問題を測る」自己循環になる）
- 既存 17 件（REV/HS/REL/KRF/GATE）は全て train 扱い（一部が exemplar 化済みのため）。DES/RC/CON は各カテゴリ 1 件を holdout に確保
- 測定時は train 一致率と holdout 一致率を**別集計**する（holdout の方が汎化性能を正しく表す）

## 計測プロトコル（§5①）

1. 被測定構成（例: 標準モデル素 / 標準モデル + harness）に `cases/` の各ケースを与え、指定の回答形式で回収する。**`expected/` を読ませない**（エージェントには読んだファイル一覧の申告を義務付ける）。DES/RC/CON は加えて **`.claude/hooks/`・`.claude/skills/` の実装・git 履歴・`docs/plans/` も読ませない**（題材の一部は実装済みで、コメント・履歴に判断根拠が残っているため。判断力でなく発掘力を測ってしまう）
2. **一次指標**: `verdict` 列挙値の完全一致率（27 件・カテゴリ別 + train/holdout 別に集計）
3. **二次指標**: `must_find` の再現率（各項目について意味的に同等の指摘があるか。採点は人間 or 別セッションの採点モデル。plausible-but-wrong な水増し findings は §5① では減点しない — verdict がズレる形で現れる）
4. 結果は `results/` に `YYYY-MM-DD-<構成名>.md` で記録する（構成・モデル・一致率・ケース別正誤）

## 測定済みベースライン

| 日付 | 構成 | verdict 一致 | 備考 |
|---|---|---|---|
| 2026-07-04 | Opus + harness（force-flag 前） | 13/17（76.5%） | [詳細](results/2026-07-04-baseline.md)。不一致は全て判断較正・事実誤りゼロ |
| 2026-07-04 | Sonnet + harness（force-flag 前） | 14/17（82.4%） | 同上。REV-01/KRF-03 は両アーム共通の不一致 |
