# ADR-0014: sidekick の ADR は下流 PJ に配布しない

## ステータス

採用（2026-05-05）— v0.7.3 で実装。

## 背景

`/adopt-sidekick-update` は `docs/decisions/*.md` 全件を機械的に下流 PJ へ配布していた。これにより以下の構造的問題が顕在化した。

1. **ADR 番号空間の汚染**: 下流 PJ が独自 ADR を持つと、sidekick 配布 ADR の番号体系と衝突する
2. **下流 PJ の ADR 索引（`docs/decisions/README.md`）の上書き**: sidekick 側索引が下流の索引を blind overwrite し、下流独自 ADR エントリが消失する
3. **ノイズ混入**: ADR は判断主体（sidekick 開発）の経緯記録であり、下流 PJ にとって直接的に意味を持たない判断（OSS 配布戦略、二リポ運用、リリース取り込み設計の内部詳細等）が下流に流れ込む

## 検討内容

### ADR の本質的役割

ADR は「設計判断の経緯記録」であり、判断主体に閉じた文書である。下流 PJ が必要とするのは「仕様の根拠」であって、その判断に至る経緯ではない。仕様自体は rules / brain / CHANGELOG に書かれていれば十分機能する。

### 配布対象の選別方式

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| **全 ADR を下流に配布しない（採用）** | docs/decisions/ は下流の領域として完全分離。下流が必要とする「仕様の根拠」は rules / brain / CHANGELOG で伝わる | 下流向け原則も配布されない（後述の通り、原則は実装に体現されており文書配布は不要） |
| ADR frontmatter で audience を指定 | 細粒度制御可 | 既存全 ADR への frontmatter 追加 + `/record-decision` 改修 |
| 配布対象を別ディレクトリに物理分離（例: `templates/decisions/`） | 物理的に明確 | ADR 移動と `/adopt-sidekick-update` の取り込みパス変更 |
| 「下流向け原則」を ADR から brain / rules に格上げ | ADR が本来の意味に純化 | ADR-0005 等の文体変換が必要 |
| 下流側で別ディレクトリにマップ（例: `docs/sidekick-decisions/`） | 番号衝突回避 | adopt 側でパス変換ロジック、運用が一段複雑 |

### 下流向け原則の扱い

下流向け原則（例: ADR-0005「下流統合非侵襲」）は実装に体現されており、`/adopt-sidekick-update` が非侵襲に振る舞うことで原則は機能する。原則の文書を下流に配布する必要はない。判断経緯を確認したい場合は sidekick リポの ADR を直接参照すれば足りる。

## 決定

`docs/decisions/` 全体を `/adopt-sidekick-update` の取り込み対象から除外する。下流 PJ の `docs/decisions/` は下流自身の領域として完全分離する。

### 実装変更

- `/adopt-sidekick-update` Step 2 から ADR 抽出（`ADRS`）を削除
- カテゴリ一括判断から `[ADR]` カテゴリを削除（`[rules]` `[skills]` `[brain]` のみ全適用対象）
- `PJ-protected files` テーブルに `docs/decisions/` 全体を追加
- Step 6.4d を「ADR 全体は取り込み対象外、更新有無は参考表示」に書き換え
- `ADR_NOTICE` で sidekick 側 ADR の更新有無を参考表示する経路は残す（リリースノート / sidekick リポへの誘導用）

### 仕様の根拠を確認する経路

| 確認したい内容 | 一次情報源 |
|---|---|
| 取り込まれたルールの趣旨 | `.claude/rules/*.md` 該当ファイル本文 |
| 思考 OS / brain 構造 | `brain/thinking.md` / `.claude/brain/thinking.md` |
| リリースの変更点・温度感 | GitHub Release / CHANGELOG.md |
| sidekick の設計判断経緯 | sidekick リポの `docs/decisions/`（直接参照） |

## 結果

### メリット

- 下流 PJ の `docs/decisions/` は完全に下流の領域。番号衝突なし、索引も自由に管理できる
- ADR が本来の意味（判断記録）に純化される
- 取り込み対象が縮小し、`/adopt-sidekick-update` の挙動がよりシンプルになる
- `docs/decisions/README.md` の上書き事故が構造的に防止される

### デメリット・リスク

- 下流が「なぜそうなっているか」を深く知りたい場合、sidekick リポを参照する手間が発生する
- 判断経緯への到達コストが上がる（ただし日常的に必要な情報ではない）

### 既存被害への対応

v0.7.2 以前で既に下流 PJ に取り込まれた sidekick ADR ファイル（例: 0007 / 0008 / 0009 / 0010 / 0012 / 0013）は、下流側で手動削除する。v0.7.3 リリースノートに該当案内を含める。

下流 PJ の `docs/decisions/README.md` が sidekick 側索引で上書きされている場合は、下流独自の索引内容に手動で復元する。

## 関連 ADR

- ADR-0005: 下流統合の非侵襲原則（下流の `docs/decisions/` を上書きしないという本決定の前提）
- ADR-0009: リリース取り込み設計（`/adopt-sidekick-update` の温度感 / 検知層の親 ADR）
