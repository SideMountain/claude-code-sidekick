# 凍結 corpus 拡充 v2 — フレームワーク設計（凍結は fresh context）

> Fable 退役対応 ⭐②P-A。既存 corpus（17 件・REV/HS/REL/KRF/GATE）に難所判断カテゴリを追加し、
> held-out 分割と worth-it 実測を導入する。**本ドキュメントはフレームワーク設計**（カテゴリ・verdict 形式・
> 測定プロトコル）。**各ケースの判定凍結（expected/*.yaml への append）は別ステップ**で、可用最上位構成（Fable）
> が fresh context で行う — append-only で二度と変更できない judgment の質を守るため（ADR-0028 決定2）。

## 1. 追加カテゴリ（§8 難所 cat1/2/3 の「判断そのもの」を測る）

既存 HS は「難所か否か」の入口判定。追加 3 カテゴリは「難所と判定した後、実際にどう裁定するか」を測る。
全て **列挙値 verdict**（一致率測定のため・既存カテゴリと同じ設計）。

| ID | カテゴリ | §8 | verdict スキーマ | 件数 |
|---|---|---|---|---|
| **DES** | 設計判断（複数案の裁定 / データモデル・API 契約） | cat1 | `decision: A\|B\|C`（提示案から選択）+ `rationale` | 4 |
| **RC** | root-cause 分析（症状→真因の推論） | cat2 | `root_cause: <候補ID>`（複数候補から1つ）+ `rationale` | 3〜4 |
| **CON** | 矛盾裁定（観点間 / 仕様と実装 / ADR と diff） | cat3 | `resolution: <選択 or 第三の道 ID>` + `rationale` | 3〜4 |

計 10〜12 件。既存 17 + 新規 = 27〜29 件。

### verdict 設計の原則（凍結可能性を担保）
- **明確に一方が優る題材に絞る**。設計判断・root-cause は自由度が高いので、「判断原則（brain §1）・rules に照らせば
  一意に決まる」ケースだけを採る。複数の正解がありうる題材は corpus に入れない（凍結の意味が消える）。
- 題材は **ccs の実判断**から採る（このセッションの #81-84 が良い供給源）。ただし PII / 固有名詞は入れない（pii-prevention）。
- must_find（rationale の核）は「この根拠に触れていれば正解の推論をしている」という**意味的アンカー**を 2〜3 点。

### ケース題材の骨子（verdict は凍結時に確定・ここでは題材のみ）
- **DES**: (a) adopt で settings.json を blind overwrite するか hooks キーのみ partial merge するか〔#81 実例〕 (b) guard の
  発火判定を先頭アンカーにするか単語境界アンカーにするか〔#82 実例〕 (c) release lint の位置非依存 grep を構造アンカーに
  するか / fence 追跡まで入れるか〔#84 実例・過剰機械化の境界〕 (d) 新規スクリプトを既存スキルに inline するか references 分離するか
- **RC**: (a) 「連結 commit だけ guard を素通りする」症状→真因（先頭アンカー vs quote 除去 vs normalize 漏れ）〔#82〕
  (b) 「standard リリースが lint で誤 fail する」症状→真因（位置非依存 grep vs title 全体 vs banner 判定）〔#84〕
  (c) WSL の index.lock 残骸で rebase 失敗→真因（並行 git プロセス vs 前回クラッシュ残骸 vs worktree 設定）
- **CON**: (a) 「検知は広げる方向のみ」と「false-deny を作らない」が衝突する guard 修正〔#82〕→ 裁定
  (b) REVIEW.md の severity 定義と scoring-guide の min() が食い違う場合〔仮想〕→ どちらを正とするか
  (c) ADR-0014（sidekick ADR 非配布）と record-decision の「ADR-0025 をアンカーに」が下流で衝突〔#83 実例〕→ 解決方向

## 2. held-out 分割（few-shot 蒸留に使わない測定専用群）

- 各ケースに `holdout: true|false` タグを付す（cases 側 frontmatter or expected 側）。
- **holdout=true 群は REVIEW.md / rubrics の few-shot exemplar に採用しない**（蒸留に混ぜると「教えた問題を測る」自己循環になる）。
- 配分: 既存 17 は全て train 扱い（既に一部が exemplar 化）。新規 10〜12 のうち **各カテゴリ 1〜2 を holdout** に確保。
- 測定時: train 一致率と holdout 一致率を別集計。holdout の方が汎化性能を正しく表す。

## 3. worth-it 実測プロトコル（§5②・7/8 以降測定不能）

「Fable 単発 vs 標準モデル + harness（ladder）」の品質・トークン差を測る。**Fable 退役前にしか Fable アームを取れない**。

1. **アーム**: (A) Fable 単発（harness なし・1 パス判定） (B) 標準モデル + harness（ladder L1-L4 + 敵対検証）
2. **対象**: 本 corpus 全 27〜29 件の verdict 一致率（expected 基準）+ トークン消費（/token-audit or usage）。
3. **一次指標**: verdict 一致率の差。**二次**: トークン/1判定・wall-clock。
4. **worth-it 判定**: 「(B) の一致率が (A) に対しどれだけ肉薄/超過するか」×「(B) のトークン増」。
   ladder が Fable 単発を代替できる証拠が出れば ADR-0028（tier 非依存化）の実測裏づけになる。
5. 結果は `results/YYYY-MM-DD-worth-it.md`。

## 4. 実施順（凍結ステップ）
1. 【本 PR】フレームワーク設計（本ドキュメント）を固める。
2. 【fresh context・Fable】DES/RC/CON の cases/*.md を書き、各 verdict を凍結して expected/*.yaml に append。README のカテゴリ表・件数を更新。holdout タグ付与。
3. 【fresh context・Fable】worth-it 実測を 2 アームで実施し results/ に記録。
4. force-flag + 較正適用後の再測定（既存 backlog ⑤）と接続。
