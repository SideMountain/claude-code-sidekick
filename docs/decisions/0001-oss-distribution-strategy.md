# ADR-0001: バージョン管理と複数プロジェクトへの配信方式

## ステータス

承認済み（2026-04-07）

## 背景

sidekick を複数プロジェクトで共有テンプレートとして使う場合、以下の課題がある:

1. テンプレートの更新を各プロジェクトに展開する仕組みがない
2. プロジェクト固有設定と汎用ルールが混在している
3. 既存プロジェクトへの後付け導入方法が未整備

## 検討内容

### 配信フロー

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| git remote で pull | 差分管理が正確 | コンフリクト管理の負担 |
| npm パッケージ化 | OSS 標準 | オーバーエンジニアリング |
| GitHub Template + Releases | 外部ユーザーに自然 | 既存PJの自動化に不向き |
| **/inventory で差分取り込み** | PJ側で自律的に取り込める | VERSION + CHANGELOG が必要 |

### PJ固有 vs 汎用の分離

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| CLAUDE.md を base / project に分割 | 機械的に上書きできる | 全PJのリファクタ必要 |
| **/inventory の差分取り込みで代替** | 最小コスト | 差分適用は人間判断 |

## 決定

1. **VERSION + CHANGELOG を導入**し、sidekick のリリースを管理する
2. **`/inventory` スキルにバージョンチェックを組み込む**。未適用の更新があれば差分を表示し、PJ側で判断して取り込む
3. **CLAUDE.md 構造分離は後回し**。`/inventory` の差分取り込みで代替する。PJ数が増えたら再検討
4. **PJ固有ファイル（task-db-integration.md, MEMORY.md, feedback_*.md）を .gitignore に追加**。`.example` ファイルを提供
5. **スキルの階層構造を導入**（SKILL.md + references/ + agents/ + templates/ 構造）

## 理由

- `/inventory` に組み込む方式は「各PJの Claude Code が自律的に取り込む」横展開フローと一致
- CLAUDE.md 分割は理想だがリファクタコストが大きく、現時点では `/inventory` で十分に代替できる
- スキルの階層構造は Claude Code が公式サポートしており、SKILL.md 1枚のフラット構造より保守性が高い

## 影響

- 新規ファイル: VERSION, CHANGELOG.md
- 新規スキル: `/inventory`
- 変更: .gitignore にPJ固有ファイルを追加
- 各PJの MEMORY.md に `sidekick_version` フィールドを追加
