# ADR-0001: sidekick OSS化 + 配信フロー設計方針

## ステータス

承認済み（2026-04-07）

## 背景

sidekickは複数PJで共通のハーネス（CLAUDE.md、skills、hooks、rules）を提供するベーステンプレートとして運用されている。しかし以下の課題がある:

1. sidekickの更新を各PJに展開する仕組みがない（手動コピー頼り）
2. PJ固有設定と汎用ルールが混在しており、OSS公開に適さない
3. 既存PJへの取り込み方法が未整備（新規PJのフォーク前提）
4. 業界で「ハーネスエンジニアリング」として体系化が進んでおり、sidekickのポジショニングを明確にすべき

## 検討内容

### 配信フロー

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| A: Tasks DB通知 + 手動取り込み | シンプル | 取り込み漏れ |
| B: git remote で pull | 差分管理が正確 | コンフリクト管理の負担 |
| C: npm パッケージ化 | OSS標準 | オーバーエンジニアリング |
| D: GitHub Template + Releases | 外部ユーザーに自然 | 内部PJの自動化に不向き |
| **E: /inventory で差分取り込み** | PJ側で自律的に取り込める | VERSION + CHANGELOGが必要 |

### 既存PJとの共存

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| フォーク（新規PJ向け） | 簡単 | 既存PJに使えない |
| 手動チェリーピック | 確実 | 手間が大きい |
| /adopt スキル | 自動化可能 | 実装コスト |
| CLAUDE.md構造分離（E案） | 自動更新しやすい | 大規模リファクタ |
| **/inventory に差分取り込みを組み込み** | 既存の仕組みに乗る | E案ほど自動化されない |

### PJ固有 vs 汎用の分離

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| CLAUDE.md構造分離（E案） | 機械的に上書きできる | 全PJのCLAUDE.mdリファクタ必要 |
| **/inventory の差分取り込みで代替** | 最小コスト | 差分適用は人間判断 |

## 決定

1. **VERSION + CHANGELOG を導入**し、sidekickのリリースを管理する
2. **各PJの /inventory にsidekickバージョンチェックを組み込む**。未適用の更新があれば差分を表示し、PJ側で判断して取り込む
3. **CLAUDE.md構造分離（E案）は後回し**。/inventoryの差分取り込みで代替する。PJ数が10以上になったら再検討
4. **PJ固有ファイル（task-db-integration.md, MEMORY.md, feedback_*.md）を .gitignore に追加**。.example ファイルを提供
5. **既存スキルのPJ固有部分を条件分岐化**（CLAUDE.md §9 の設定有無で動作を切り替え）
6. **スキルの階層構造を導入**（SKILL.md + references/ + agents/ + templates/ 構造）

## 理由

- /inventory に組み込む方式は「各PJのClaude Codeが自律的に取り込む」という横展開フローと一致
- E案は理想だがリファクタコストが大きく、現時点では/inventoryで十分に代替できる
- スキルの階層構造は公式サポート済みであり、SKILL.md 1枚のフラット構造より保守性が高い

## 影響

- 新規ファイル: VERSION, CHANGELOG.md
- 新規スキル: /inventory
- 変更: close-chat, weekly-review のPJ固有部分を条件分岐化
- 変更: .gitignore にPJ固有ファイルを追加
- 変更: 大きいスキルを階層構造にリファクタ
- 各PJの MEMORY.md に sidekick_version フィールドを追加
