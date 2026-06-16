# ADR-0020: Spine-Driven Development の棚卸しと構想の凍結（ledger 型）

## ステータス

採用（2026-06-17）— **ledger 型**（新機能を 1 つも決めない「地図」）

## 注記: これは「決定」ではなく「地図」

この ADR は新機能・新スキル・新動詞・新 hook を **一切導入しない**。既存 ADR の live/superseded 関係を棚卸しし、"Spine-Driven Development" 構想の各柱を「認識済み・未着手・moat 線引き付き」で凍結記録する **台帳（ledger）** である。本文中で言及する構想（軽量 intake・Observability 等）を「採用済み」と誤読しないこと。前進の前提条件を満たした柱だけが、将来それぞれの ADR で改めて起草される。

## 背景

"Spine-Driven Development（背骨駆動）" を次の構想として温めていた（5 本柱: Spine = 背骨 docs / Loop = 最小能動面 / Gate = 検証 / Model-tiering / Observability）。これを上位 ADR 化すべく、5 本柱それぞれの設計案を起こし、敵対的レビューと全 ADR 整合チェックにかけた。

検証の結論として、**「5 本柱が 1 本の因果鎖に収束する新しい組織化原理」という前提は成立しなかった**。

- 実体化済みの 4 機構（判断 = ADR-0016 / Loop = ADR-0018 / Gate = `/tune` + `/review` + `/verify` / 強制層 = ADR-0002）は、相互に入出力を渡し合う「鎖」ではなく **直交した独立機構**である。ccs を貫く真の組織化軸は、`docs/design.md` が既に持つ **「仕組み化 3 層（認知 → 強制 → 検知）」**。
- 鎖の起点とされた柱 1 Spine（色宣言）は **実体ゼロ**（`design-system.md` 不在・PostToolUse hook 未配線を実地検証）。起点が無い以上「既にある鎖を読むだけ」という前提が崩れる。
- 5 つの設計提案すべてが follow-up ADR を要求した。これは **実装が前進していない柱ほど ADR 化したがる scope creep の症状** であり、PJ brain が自認する失敗パターン「未着手構想への過剰投資 / 70% → 90% ループ」に該当する。

よって grand な上位組織化 ADR は **過剰設計** と判断した。一方、設計探索で得た 2 つの成果（ADR の supersede 棚卸し / 構想の moat 線引き）は durable に残す価値がある。本 ADR はその受け皿である。

## 決定

ADR-0020 を ledger 型として、以下 3 点のみを確定する。新機能は導入しない。

### 決定 1: brain / positioning 系 ADR の live/superseded 棚卸し

| ADR | live/superseded | 棚卸しメモ |
|---|---|---|
| 0007 思考 OS positioning | **live**（extend 対象） | Spine-Driven は supersede せず extend。核「judgment that compounds（知識の複利）」を保存する |
| 0010 思考 OS 2 層(L0/L1) + 配布・還流 | **一部 superseded**（by 0013） | live: `@import` 配布 + 双方向（配布/還流）メカニズム。廃止: 「PJ 配下 thinking.md v1.0 廃止」案（0013 で取り下げ）・L0/L1 等の旧層名称（0016 が個人/PJ へ再整理） |
| 0013 brain 3 層(L0/L1/L2) | **superseded by 0016** | 当初ドラフト。0010 の supersede 関係は 0016 経由で継承される |
| 0016 brain 2 層(個人/PJ) | **live**（現行確定形） | 0013 を一部 supersede。※ADR 内の status ラベルは「ドラフト」のまま（昇格は別途の cleanliness 項目） |
| 0018 北極星と最小ループ | **live** | 全柱の評価基準。「能動層は 3 動詞に限定・新動詞を増やさない」原則の源 |
| 0019 UI/UX ハーネス | **live**（v0.8.x P1 未実装） | `design-system.md` / PostToolUse hook は決定のみで未配線。Spine 柱の **UI 特化インスタンス** |

**廃止概念の注意**: 後続セッションは L0/L1/L2（3 層）・思考 OS の旧還流タグ（`[L0候補]`/`[L1候補]`/`[L2固有]`）を引かないこと。現行は brain **2 層（個人 brain / PJ 固有 brain）** + 還流タグ `[OSS 還流候補]`/`[個人 brain 昇格]`/`[PJ 固有]`（ADR-0016）。

### 決定 2: "Spine-Driven" 構想の各柱を「認識済み・未着手・moat 線引き付き」で凍結

実体化済みの 2 柱（Gate / 判断）は決定 1 で live と整理済みのため、凍結対象は未実体の柱に限る。**follow-up ADR の番号事前予約はしない**（後述）。

| 柱 | 現状 | 前進の前提条件 | moat 線引き |
|---|---|---|---|
| Spine（色宣言 DESIGN/BRAND + 逸脱検知） | 骨組みのみ（UI のみ・大半未実装） | ADR-0019 v0.8.x P1 完遂 + UI 下流 dogfood | 生成は外部・検知が ccs。ADR-0019 を再発明せず brand/arch へ一般化。新動詞ゼロ |
| Loop intake（Slack/Issue/chat → 議論 → 着手） | 構想（N=1） | Slack signal/noise 実測（自 PJ 直接メンション/明示言及に限定・既定 false） | `/inventory` の read-only ソース一般化として吸収。write-back 禁止・外部 DB を SoT 化しない。新動詞ゼロ |
| Model-tiering（局面別モデル） | 構想（N=1・グリーンフィールド） | frontmatter 散在の DRY 課題 or 局面誤適用による品質劣化の実観測 | 切替/実行は公式 `opusplan`/`effort` に委任。ccs は認知レイヤーのみ（検知は false-positive リスクで見送り）。「柱」でなく「公式機能への薄い認知レイヤー」 |
| Observability（system viz + token/data） | 構想・**凍結** | ① ccs スラグへの auto-memory 移設完了 ② JSONL transcript スキーマの安定確認 ③ moat 線引き合意 | generic observability SaaS / 外部 DB の再発明は NG。ccs が描くのは Claude Code セッション角度（token/data/ループ）のみ・runtime（FE→API→DB）は外部 thin adapter へ委譲 |

### 決定 3: 「5 本柱の組織化原理」として現時点では定式化しない

鎖の起点（柱 1 色宣言）の実体ゼロが検証で判明したため、Spine-Driven を「組織化原理」として ADR で主張しない。"Spine-Driven" は MEMORY.md の構想ラベルとして保持する。将来、実装が前進した柱が 3 つ以上揃った時点で、上位 ADR としての再定式化を改めて検討しうる（現時点では留保）。

## 理由

1. **拡張ファースト / 新規追加は最終手段**: 既存 ADR が既に生む coherence に名前を先付けしない。検証で前提が空洞と判明した以上、grand ADR は意図のない文書になる
2. **70% で動く / スコープ外は認識済み・未着手と明示**: 構想を moat 線引き付きで凍結記録するのは PJ brain の原則そのもの
3. **knowledge-map「正しいレイヤーに 1 つ強く置く」**: supersede 関係は decision-history であり、`docs/decisions/` が正史。索引（README）でも私的メモリでもなく ADR が受け皿
4. **北極星（ADR-0018）**: 能動スキル・新動詞・新 hook ゼロ。地図は評価基準として効くだけで、能動面を増やさない
5. **誇張せず記録する**: 検証が前提の空洞を明らかにした事実をそのまま残す。構想の大半について「現時点では実装・定式化しない」と判断したこと自体を、後続が同じ再検討を繰り返さないために記録する

## 却下した案

- **案 C「5 本柱の組織化モデル ADR」**: 起点（色宣言）の実体ゼロを検証で確認。前提が成立しないため却下
- **follow-up ADR（0021〜）の番号事前予約**: 「N 枠を埋めにいく」前進圧を生む（地図に描いた未踏地は探検を誘発する）。番号は実際に起草する時点で振る
- **ADR を一切切らない案（README 追補 + 私的メモリ据え置き）**: supersede 棚卸しを README 索引に置くと decision 意味論が索引レイヤーに混じる。構想凍結の根拠も非 git の私的メモリに留まり、共有性・durable 性を欠く

## 影響

- 新規ファイルは本 ADR 1 本のみ。`docs/design.md` は変更しない（「決定史なしの今日のダイジェスト」という自己宣言を尊重し、Spine-Driven 節も Model-tiering/Observability 節も追加しない）。README 索引に 1 行追加する
- 構想を前進させる唯一の地に足ついた次手 = **ADR-0019 v0.8.x P1（`design-system.md` テンプレ + PostToolUse hook 実配線）の UI 領域完遂 → UI 下流 dogfood**。これが柱 1 の brand/arch 一般化の前提
- ADR-0014 準拠: 本 ADR は配布リポの canonical home に留まり、下流 fork には流れない

## 関連 ADR

- ADR-0007 / 0010 / 0013 / 0016: 棚卸し対象（brain / positioning 系）
- ADR-0018: 北極星と最小ループ（全柱の評価基準）
- ADR-0019: UI/UX ハーネス（Spine 柱の UI 特化インスタンス・P1 完遂が次手）
- ADR-0002 / 0006: 横断の強制層 / dogfood 基盤
