# ADR-0013: 思考OS の 3 層 brain 構造

## ステータス

一部 Superseded by ADR-0016（2026-05-08）。当初ドラフト（2026-04-28）。

ADR-0016 が以下を再定義:
- 3 層構造（L0/L1/L2）→ 2 層構造（個人 brain + PJ 固有 brain）
- chain `@import` → 単純 1 段 `@import`
- 還流タグ 3 層化 → 2 層化

ADR-0013 で確定し維持される決定:
- `brain/` ディレクトリ命名
- PJ 配下 brain の永続化（ADR-0010 の v1.0 廃止予定を取り下げ）
- 判定軸「PJ 横断か PJ 固有か」

当初の ADR-0010 supersede 関係は ADR-0016 経由で継承される。

## 背景

### PJ 固有判断軸の構造的な置き場

ADR-0010 で思考OS を L0（共通ベース）+ L1（個人差分）の 2 層構造として定義した。一方、CLAUDE.md §1「オーナーの判断軸」は次の構造を持つ:

- thinking.md（人スコープ）への参照
- + PJ 固有の追加判断軸（拡張ファースト、完成度よりタイミング 等）

「個人の判断軸」と「PJ 固有の判断軸」は実態として既に分離されているが、2 層構造ではこの区別を文書構造に表現できない。PJ 固有判断軸（PJ のドメイン・成熟度・チーム文化に依存）と個人判断軸（複数 PJ を跨ぐ個人の癖）はスコープが異なるため、L1 への統合は無理筋。

### 命名の中立性

`neotion/` は ADR-0007 由来の命名で、特定のサービス名を含む。OSS の配布物の構造名としては中立な命名が望ましい。

### @import の振る舞い

Claude Code の `@path/to/file` は最大 5 ホップで再帰解決される（公式ドキュメント: code.claude.com/docs/en/memory）。3 層 chain を `@import` で構造強制でき、各層の差分を物理的に DRY にできる。

## 検討内容

### 層数

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| 2 層（L0/L1） | シンプル | PJ 固有判断軸の構造的な置き場が無い |
| **3 層（L0/L1/L2）** | スコープごとに分離、文書構造が実態を反映 | 層が増える |

### 命名

| 候補 | 評価 |
|--------|------|
| `neotion/` | サービス名に依存 |
| `thinking-os/` | 中立だが冗長 |
| **`brain/`** | 短く、外側（擬人化）と内側（系）を橋渡しする語。3 層全てで統一可能 |
| `mind/` | 内面寄りで、L0 の業界共通軸に当たらない |

### PJ 配下 thinking.md の扱い

| 選択肢 | 帰結 |
|--------|------|
| ADR-0010 通り廃止 | PJ 固有判断軸の構造的な置き場が消失、CLAUDE.md §1 で受け続ける混在状態 |
| **L2 として永続化** | スコープごとの分離が完成、CLAUDE.md は規約に純化 |

## 決定

### 1. 3 層 brain 構造を採用

| 層 | スコープ | 配置 |
|---|---|---|
| **L0: base brain** | 全人類（業界共通の判断軸） | sidekick リポ `brain/`、ccs 経由でホームに展開 |
| **L1: personal brain** | 1 人（複数 PJ 横断の個人判断軸） | `~/.claude/brain/thinking.md` |
| **L2: project brain** | 1 PJ（PJ 固有判断軸） | `<PJ>/.claude/brain/thinking.md` |

判定基準: **「同じ自分が別 PJ に行ってもこの判断するか?」** YES → L1、NO → L2。迷った場合は L2 から始め、3 件ルールで L1 に昇格させる。

### 2. `@import` チェーン

```
<PJ>/.claude/brain/thinking.md          (L2)
  └─ @~/.claude/brain/thinking.md       (L1)
       └─ @~/.claude/ccs/brain/thinking.md  (L0、相当パス)
```

深さ 3。Claude Code の 5 ホップ制限内。具体的なホーム展開先のパスは `/adopt-sidekick-update` スキルに委ねる。

### 3. 命名は `brain/` で統一

L0 / L1 / L2 すべてで `brain/` ディレクトリを使用。文脈（パス）で層を区別する。

### 4. PJ 配下 brain は永続化

ADR-0010 の「v1.0 で PJ thinking.md 廃止」決定を取り下げる。L2 brain として恒久化する。v1.0 の破壊変更内容は別 ADR で再定義する。

### 5. CLAUDE.md §1 は縮約

§1 の「PJ 固有判断軸」内容を `.claude/brain/thinking.md` (L2) に移動。§1 は brain への参照（`@.claude/brain/thinking.md`）に縮約。CLAUDE.md は HARD ルール・ゲート・Lessons Learned 等の規約専用に純化する。

### 6. 還流タグの 3 層化

- `[L0候補]`: 業界共通の判断軸（ccs 還流候補）
- `[L1候補]`: 個人の判断軸（複数 PJ 横断、ホーム L1 昇格候補）
- `[L2固有]`: PJ 固有判断軸（L2 永続化）

3 件ルール:
- PJ 内同類 3 件 → L2 昇格
- 別 PJ で同類観測 → L1 昇格
- OSS で業界共通と判明 → L0 昇格（ccs 還流）

## 理由

### 既存活用ファースト

CLAUDE.md §1 が事実上 L2 brain を保持しており、それを構造として明示する形で実装する。新規概念を導入していない。

### DRY の構造強制

`@import` で各層の差分を物理的に管理する。L1 = L0 + 差分、L2 = L1 + 差分。重複は構造で防がれる。

### 役割の純化

brain = 判断軸、CLAUDE.md = 規約 と責務を分離する。各層の役割が文書構造に反映される。

### 命名の中立性

`brain/` は特定のサービス名・組織名に依存しない、配布物として永続使用可能な名称。

## 却下した案

- **2 層維持**: PJ 固有判断軸の構造的な置き場が確保できない
- **`thinking-os/` 命名**: 中立だが冗長。`brain/` で同等の意図が短く表現できる
- **`mind/` 命名**: 内面寄りで、L0 の業界共通軸を含む語としては軽い

## 影響

### 変更が入るファイル

- `docs/decisions/0010-thinking-os-layers-and-reflow.md`: ステータスを「一部 Superseded by ADR-0013」に更新
- `docs/decisions/README.md`: ADR-0013 追加、ADR-0010 ステータス更新
- `brain/thinking.md`（新規、sidekick リポ配布元）: L0 マスター
- `.claude/rules/thinking.md`: 廃止、または `@brain/thinking.md` の薄い import に縮約
- `CLAUDE.md §1`: 縮約。PJ 固有判断軸を `.claude/brain/thinking.md` に移動
- `.claude/brain/thinking.md`（新規、L2）: sidekick PJ 自身の L2 brain
- `.claude/rules/knowledge-map.md`: 3 層階層と還流タグを反映
- `.claude/skills/setup/SKILL.md`: 3 層構造のセットアップ選択肢を追加
- `.claude/skills/close-chat/SKILL.md`: 還流タグ 3 層化
- `.claude/skills/weekly-inventory/SKILL.md`: 還流タグ 3 層化
- `.claude/skills/adopt-sidekick-update/SKILL.md`: ホーム L0 展開（最小実装）
- `.claude/skills/sync-oss/SKILL.md`: `brain/` ディレクトリの同期対応
- `CHANGELOG.md`: v0.7.0 (unreleased) に記載

### バージョン方針

- Phase 1 実装は v0.7.0（minor bump、機能追加）
- ADR-0010 の v1.0 廃止予定だった「PJ thinking.md」は取り下げ。v1.0 の破壊変更内容は別 ADR で再定義する

### /setup の 3 層構造選択肢

新規 PJ セットアップ時に以下を選べる:

- (a) PJ 配下に thinking.md を物理コピー（旧 ADR-0010 互換、team 利用向け）
- (b) ホーム L1 のみ import（個人・複数 PJ 利用向け）
- (c) **3 層構造（推奨）**: L0 + L1 + L2 の `@import` chain

### sidekick 自身のテンプレ提供時の取扱

sidekick の `.claude/brain/thinking.md` は sidekick PJ 固有の L2 を保持する。`/setup` で下流 PJ にテンプレートを配布する際は L2 をクリーンアップし、PJ 固有判断軸を流出させない。

### 既存下流 PJ の移行

既存 `.claude/rules/thinking.md` は過渡期は共存可。`/adopt-sidekick-update` で 3 層構造への移行を案内する。強制移行は行わない。

### 今後注意すべき点

- L1/L2 境界判定は主観。「別 PJ でも同じ判断するか」基準と 3 件ルールで運用
- `@import` 5 ホップ制限を超える設計は避ける（現状深さ 3）
- L2 → L1 昇格は別 PJ 観測が必要。`/weekly-inventory` で複数 PJ 横断スキャンを実装する（Phase 2 の `brain-reflow` で扱う）

### 関連 ADR

- ADR-0007: thinking.md = 人に紐づく入れ替え可能な思考OS（基盤思想）
- ADR-0010: 2 層構造（一部 Superseded）。配布・還流メカニズムの全体設計は継承
- ADR-0007 / ADR-0010 で言及されたスタンドアロン版独立リポ化構想は別途扱う
- 個人専用 skill/hook（`~/.claude/skills/` `~/.claude/hooks/`）の扱いは別 ADR（射程外）
