# ADR-0016: brain の 2 層モデル化と上書き禁止運用

## ステータス

ドラフト（2026-05-08）

ADR-0013「思考OS の 3 層 brain 構造」を一部 supersede する:
- 3 層構造（L0/L1/L2）→ 2 層構造（個人 brain + PJ 固有 brain）
- chain `@import` → 単純 1 段 `@import`
- 還流タグ 3 層化 → 2 層化
- L0 home 展開構想 → OSS テンプレート（ロード対象外）として保持

維持される ADR-0013 の決定: `brain/` ディレクトリ命名、PJ 配下 brain の永続化、判定軸「PJ 横断か PJ 固有か」。

## 背景

### chain `@import` の運用脆弱性

ADR-0013 が想定する L2 → L1 → L0 の transitive 解決は、L1（`~/.claude/brain/thinking.md`）が存在する場合にのみ成立する。Claude Code の `@import` は対象ファイル不在時に silent ignore する仕様のため、L1 不在で chain は L1 段で破断し、L0 が context に到達しない。

L1 配置を必須とする検知層が hooks / スキルに存在しないため、L1 不在による chain 破断は静かに発生し、利用者・開発者ともに気付かないまま運用が継続するリスクがある。

### L0/L1 のコンテンツ境界の主観性

ADR-0013 の判定基準「同じ自分が別 PJ に行ってもこの判断するか?」は L1 vs L2 を区別するが、L0 vs L1 の境界は「業界共通」「個人の癖」という主観評価に依存する。判断軸の追加・更新時に毎回判定コストが発生する。

### 利用者ワークフローとの不整合

sidekick / ccs リポを clone しない利用者にとって、L0（sidekick リポ内 `brain/thinking.md`）は実行時にアクセスできない。ADR-0013 は「L0 を home に展開する仕組みは `/adopt-sidekick-update` に委ねる」としたが、具体実装のないまま運用されていた。

### 個人 brain の上書きリスク

L0 の更新を利用者が取り込む際、個人 brain（L1）が自動上書きされる経路が設計上閉じられていなかった。育てた判断軸を失う事故の温床になり得る。

## 検討内容

### 層数

| 選択肢 | 評価 |
|--------|------|
| 3 層維持（L0/L1/L2） | 配布主体は分離されるが、L0/L1 のコンテンツ境界が主観的。個人運用では overkill |
| **2 層（個人 brain + PJ 固有 brain）** | コンテンツ的に意味のある分離は「個人横断」「PJ 固有」の 2 つ。OSS 配布物は「テンプレート素材」として 2 層の外に位置づける |
| 1 層（PJ brain のみ） | PJ 横断の判断軸を保持できない |

### `@import` 構造

| 選択肢 | 評価 |
|--------|------|
| chain（PJ → 個人 → OSS） | L1 不在時の chain 破断リスクが残る |
| 並列（PJ → 個人, PJ → OSS） | 一方不在でも他方到達。フェイルセーフ性が高いが、2 層モデルでは並列の必要がない |
| **単純 1 段（PJ → 個人）** | 2 層モデルでは PJ brain が個人 brain を 1 段で import すれば完結。OSS はロード対象外で構造に現れない |

### OSS テンプレートの位置づけ

`sidekick/brain/thinking.md` は OSS 配布物のテンプレート素材として保持し、ロード対象外とする（CLAUDE.md からも他ファイルからも `@import` しない）。

| 役割 | 説明 |
|------|------|
| 配布素材 | sidekick リポに git 管理される「個人 brain の初期テンプレート」 |
| `/setup` の入力 | 利用者の `~/.claude/brain/thinking.md` 不在時に、テンプレートからコピーされる |
| `/adopt-sidekick-update` の差分元 | 利用者の個人 brain との差分を提案する元データ |

### 個人 brain の上書き禁止運用

個人 brain は「育てるもの」であり、自動上書きしてはならない。スキル別の振る舞いを以下のように定める。

| スキル | 個人 brain への振る舞い |
|--------|---------------------|
| `/setup` | 不在時のみテンプレートからコピー。存在時は触らない |
| `/adopt-sidekick-update` | 自動上書き禁止。差分提案のみ。マージは利用者判断 |
| その他 | 触らない |

## 決定

### 1. 2 層 brain モデルを採用

| 層 | 配置 | スコープ | ロード対象 |
|---|---|---|---|
| **個人 brain** | `~/.claude/brain/thinking.md` | 個人（複数 PJ 横断） | ✅ |
| **PJ 固有 brain** | `<PJ>/.claude/brain/thinking.md` | 1 PJ | ✅ |

OSS テンプレート（`sidekick/brain/thinking.md`）は配布素材として保持し、ロード対象外とする。

判定基準: **「全 PJ で適用したい判断軸か?」** YES → 個人 brain、NO → PJ 固有 brain。

### 2. `@import` 構造は単純 1 段

```
<PJ>/CLAUDE.md
  └ @.claude/brain/thinking.md       (PJ 固有 brain)
       └ @~/.claude/brain/thinking.md  (個人 brain)
```

深さ 2 で完結（5 ホップ制限から余裕）。個人 brain 不在時は silent ignore され、PJ brain だけがロードされる（フェイルセーフ）。

### 3. 個人 brain 上書き禁止運用

`/setup` は初期化時のみコピー、`/adopt-sidekick-update` は差分提案のみで自動上書きしない。

### 4. 還流タグの 2 層化

| 旧（ADR-0013） | 新（ADR-0016） |
|---|---|
| `[L0候補]` | `[OSS 還流候補]` — 個人 brain で確立した原則を OSS テンプレートに PR で還流 |
| `[L1候補]` | `[個人 brain 昇格]` — feedback が複数 PJ 横断で蓄積 → 個人 brain に追記 |
| `[L2固有]` | `[PJ 固有]` — PJ brain に閉じる |

3 件ルール:
- PJ 内同類 3 件 → PJ brain 昇格
- 別 PJ で同類観測 → 個人 brain 昇格
- 業界共通と判明 → OSS テンプレート還流（手動 PR で sidekick リポへ）

### 5. 健全性チェック

session-start hook で `~/.claude/brain/thinking.md` の存在を確認し、不在時に warning を出す。利用者の `/setup` 漏れを検知する（PJ brain は load されるが、個人 brain が不在で silent ignore されている状態を可視化する）。

## 理由

### 動作担保

Claude Code の memory 機能（公式ドキュメント記載 + 実環境検証で確認済み）の以下の挙動を前提とする:

- 非 CLAUDE.md ファイル内の `@import` も transitive 解決される
- 同一ファイル内の複数 `@import` の並列展開
- 相対パス（インポート元起点）と絶対パス、`~/` 展開
- 対象ファイル不在時の silent ignore

これらにより、2 層モデル + 1 段 `@import` の構造は Claude Code の memory 機能で完全に実現可能。

### 主観判定コストの削減

「業界共通か個人の癖か」を毎回判定する必要がなくなる。判断軸の追加先は「全 PJ で適用したいか」だけで決まる。

### フェイルセーフ性

個人 brain 不在時でも PJ brain はロードされる。chain 破断による silent failure が原理的に発生しない。

### 利用者ワークフローの単純化

利用者は ccs リポを持たなくても、`~/.claude/brain/thinking.md` を所有・編集するだけで運用可能。`/setup` でテンプレートからの初期化が一度だけ走り、以降は利用者が育てる。

### 上書き事故の予防

個人 brain は明示的に「上書き禁止」運用。育てた判断軸を失う事故が構造的に防がれる。

## 却下した案

- **3 層維持**: コンテンツ境界の主観性、L0/L1 の運用上の重複、個人運用での overkill が解消されない
- **chain `@import` 維持**: L1 不在時の silent ignore による chain 破断リスクが残る
- **L0 を home に同期する仕組み**: 同期メカニズムの実装コストに対して、テンプレート素材として保持する方が単純
- **並列 `@import`（PJ → 個人 + PJ → OSS）**: 2 層モデルでは OSS をロード対象としないため、並列の必要がない

## 影響

### 変更が入るファイル

- `docs/decisions/0013-brain-three-layer-structure.md`: ステータスを「Superseded by ADR-0016」に更新
- `docs/decisions/README.md`: ADR-0016 追加、ADR-0013 ステータス更新
- `CLAUDE.md §1`: 2 層モデルの記述に更新、`@import` 構造の説明変更
- `brain/thinking.md`: ファイル冒頭の説明を「OSS テンプレート、ロード対象外」に更新
- `.claude/brain/thinking.md`: 個人 brain への 1 段 `@import` に整理（`@~/.claude/brain/thinking.md`）
- `.claude/rules/knowledge-map.md`: 2 層モデルの記述、還流タグの 2 層化、判断フローの更新
- `.claude/rules/code-quality.md` 等の L0 言及: 「個人 brain」表現に更新
- `.claude/skills/setup/SKILL.md`: 個人 brain 初期化ロジック追加（不在時のみコピー）
- `.claude/skills/adopt-sidekick-update/SKILL.md`: brain は自動上書き禁止、差分提案のみ
- `.claude/skills/close-chat/SKILL.md`: 還流タグ 2 層化
- `.claude/skills/weekly-inventory/SKILL.md`: 還流タグ 2 層化
- `.claude/hooks/session-start.sh`: 個人 brain 存在チェック追加
- `CHANGELOG.md`: v0.8.0 (unreleased) に記載

### バージョン方針

v0.8.0 として minor bump でリリースする。0.x.y 系列のため破壊変更も minor で扱える（semver の「0.x は unstable」規約）。v1.0 は将来の大型マイルストーンに留保する（ADR-0011 で予約済み、内容未定）。

### sidekick リポ自身の扱い

sidekick リポも他の PJ と同じ構造に従う（自己適用）。

- `<sidekick>/.claude/brain/thinking.md` は sidekick PJ 固有 brain としてロードされる
- `<sidekick>/brain/thinking.md` は OSS テンプレート素材としてロード対象外
- sidekick 開発時も個人 brain（`~/.claude/brain/thinking.md`）が PJ brain から transitive import される

sidekick リポ内でテンプレート（`brain/thinking.md`）を編集することは「OSS 配布物の更新」を意味し、その編集が sidekick 開発時の context に直接反映されるわけではない。テンプレートの効果を確認するには、利用者と同じく `/adopt-sidekick-update` 経由で個人 brain にマージする必要がある。

### 既存下流 PJ の移行

リリース後、各下流 PJ で `/adopt-sidekick-update` を実行することで反映される。具体的な変更点:

- `<PJ>/.claude/brain/thinking.md` の `@import` 行を `@~/.claude/brain/thinking.md` に統一
- `~/.claude/brain/thinking.md` 不在の利用者は、`/setup` でテンプレートから初期化される（既存利用者は対話的にコピーを承認）
- PJ 固有 brain（`.claude/brain/thinking.md`）の中身は変更されない
- PJ ローカルの `brain/thinking.md`（過去の取り込みで残ったもの）は load 対象外なので害はないが、`/adopt-sidekick-update` で清掃候補として提示する

### 関連 ADR

- ADR-0007: thinking.md = 入れ替え可能な思考OS（基盤思想、維持）
- ADR-0010: 2 層構造（一部 Superseded by ADR-0013、本 ADR で再整理）
- ADR-0013: 3 層 brain 構造（本 ADR が一部 Supersede）
- ADR-0011（予約）: v1.0 破壊変更内容（引き続き未定）
- ADR-0015: 下流 PJ の ccs 不意識運用原則（本 ADR は同原則に整合）
