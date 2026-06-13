# ADR-0009: リリース取り込み設計（温度感・思想漏洩防止・スキップ制御）

## ステータス

採用（2026-04-18）— **P1 + P2 + P3 全範囲実装完了**。認知→強制→検知の3層が揃った。

**実装補足（P2 実装時の設計調整）**:
- `/inventory` を軽量化（**Critical のみ強調表示**）、Standard/Enhancement は 1行サマリに変更
- 全 severity の深い棚卸しは `/weekly-inventory` に委譲（/inventory の頻度を考慮した UX 最適化）
- `/weekly-review` を `/weekly-inventory` に rename（実態が inventory 系のため命名整合）
- `/adopt-sidekick-update` UX をファイル単位ループから **カテゴリ一括判断（default）** に変更。`--all` / `--careful` モードあり
- `/setup` に ccs remote 自動追加ステップ

**実装補足（P3 検知層）**:
- Critical 未取込フラグ: `auto-memory/project_critical_pending.md`（存在 = pending）
- `/inventory` Critical 検知時にフラグ作成、`/adopt-sidekick-update` 取り込み成功時にフラグ削除
- `session-start.sh` がフラグの有無をチェック → warning 継続表示（取り込み忘れ防止）
- `/weekly-inventory` で Critical の経過日数を表示（3日で警告、8日で「即対応推奨」）

**実装補足（severity の機械マーカー化）**:
- リリース body 冒頭に機械可読な severity マーカー（`> severity: critical|standard|enhancement`、見える行）を必須出力する
- `/inventory`・`/adopt-sidekick-update` はこのマーカーを**一次ソース**として読み、マーカーのない旧リリースは title prefix にフォールバックする
- title prefix・body banner・severity マーカーの**3 点を必ず一致**させる。title prefix のみを機械検知対象とすると body を読まずに終わる弱点があり、機械可読マーカーでこれを閉じる
- HTML コメント形式は配信先のサニタイズで欠落しうるため使わず、見える行で確実に残す

## 背景

v0.5.0 リリース切り時（2026-04-18）に、以下の構造的課題が顕在化した:

1. **思想漏洩**: `/inventory` は GitHub Releases のリリースノートを表示するだけ。リリースノートに書き漏れた ADR / rules の変更は下流に伝わらない
2. **取り込み方式未定義**: `/inventory` が差分を提示した後、どう取り込むかの手順がない。「更新が必要です。メインに戻って取り込み判断を行ってください」で終わる
3. **温度感の欠如**: 緊急バグ修正（stop hook 無限ループ等）と通常機能追加が同じ扱い。下流 PJ は緊急度を判断できない
4. **スキップ制御なし**: 取り込まない判断をしても記録されず、次の `/inventory` で同じ差分が再提示される

## 検討内容

### リリースノートの信頼性向上

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| **機械的な変更リスト自動生成（採用）** | 書き漏れゼロ | スキル実装が必要 |
| リリースノート書式規約化 | ルール作成のみで実装不要 | 人間の書き漏れは防げない |
| 自動生成のみ、人間記述なし | 最もシンプル | 「なぜ」の記述が弱くなる |

### 温度感の分類粒度

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| 2段階（緊急 / 通常） | シンプル | 拡張（opt-in）を区別できない |
| **3段階（緊急 / 通常 / 拡張、採用）** | バランス良い | — |
| 5段階（security / critical-bug / feature / enhancement / docs） | 細かい | 過剰設計、分類迷い |
| semver 依存 | 分類不要 | patch でも緊急と非緊急が混在する |

### 温度感の伝達方式

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| GitHub Release title prefix のみ | シンプル | body 読まずに終わる可能性 |
| body banner のみ | 詳細伝達可 | タイトルで気づけない |
| **title prefix + body banner（採用）** | 二重化で見落とし防止 | 二箇所で一致維持が必要 |
| GitHub Labels | ネイティブ | /inventory が label API 叩く必要、gh api が重い |

### スキップ記録の格納先

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| CLAUDE.md に `adopted_skips` セクション | git 管理、チーム共有 | 下流 PJ ルートを汚染（ADR-0005 原則違反） |
| CLAUDE.local.md | 個人ローカル | 手動管理、記述フォーマット不統一 |
| **auto-memory `project_skipped_updates.md`（採用）** | Claude 管理、個人ローカル、feedback_*.md と同じ系列 | auto-memory 前提が必要（ADR-0008 で整備済み） |

## 決定

### P1: リリース側の整備（本 PR で実装）

1. **`/release` スキル新規作成**
   - 対話的に温度感・バージョン判定
   - 前回タグ以降の変更 ADR / rules / skills を **機械的にリストアップ**してリリースノートに含める
   - CHANGELOG bump（`[Unreleased]` → `[x.y.z]`）
   - tag + GitHub Release 作成

2. **温度感の3段階分類**
   - **Critical**: セキュリティ / 致命的バグ修正。即取り込み推奨
   - **Standard**: 通常の機能追加・修正（デフォルト。プレフィックスなし）
   - **Enhancement**: opt-in な改善。後回し可

3. **GitHub Release フォーマット規約**
   - **title prefix**: Critical → `⚠️ [CRITICAL] vX.Y.Z — …`、Standard → `vX.Y.Z — …`、Enhancement → `💡 [ENHANCEMENT] vX.Y.Z — …`
   - **body banner**: severity に応じた文言を冒頭に配置
   - **機械リスト**: `## 変更された設計判断 (ADR)` / `## 変更された rules` セクションを必ず含める

4. **CHANGELOG.md フォーマット更新**
   - intro に severity 3段階の説明を追加

5. **README.md / README.ja.md の Versioning 節**
   - severity の説明を追加

### P2: 取り込み側の整備（後続）

6. **`/adopt-sidekick-update` スキル新規**（予定）
   - `/inventory` で検知した差分を対話的に適用
   - ファイルごとに「取り込む / 永久スキップ / 後回し」を選択

7. **`/inventory` 改修**（予定）
   - Release title / body の severity を読み取り
   - Critical は強調表示、スキップ不可または理由必須
   - スキップ済み項目（auto-memory 参照）を「前回スキップ」として表示

8. **スキップ記録フォーマット**（予定）
   - `auto-memory/project_skipped_updates.md` に永久/後回しを区別して記録

### P3: 強制・検知層（後続）

9. **session-start.sh 改修**（予定）
   - Critical リリースが未取込の場合、session 開始時に warning を継続表示

10. **`/weekly-inventory` 改修**（予定）
    - 未取込の更新（特に Critical）を棚卸しレポートで可視化

### 適用範囲

- **sidekick と claude-code-sidekick の両方**で同じリリースフォーマットを採用
- `/release` スキルは両リポで共通に使える設計にする

## 理由

1. **仕組み化の3層（thinking.md §1）**: 「認知（`/inventory`）→強制（session-start warning）→検知（`/weekly-inventory`）」を全て満たす
2. **DRY**: `/release` スキルが1箇所で「変更ADR/rules の機械リスト」を担保 → リリースノートの書き漏れゼロ
3. **既存活用ファースト（thinking.md §1）**: auto-memory（ADR-0008 で整備済み）を活用してスキップ記録、新しいデータストアを作らない
4. **ADR-0005 下流統合原則の尊重**: スキップ記録は auto-memory（個人ローカル）で、下流 PJ ルートを汚染しない

## 影響

### sidekick リポ
- 新規: `.claude/skills/release/SKILL.md`、`.claude/skills/release/references/release-format-spec.md`、`docs/decisions/0009-release-adoption-design.md`
- 更新: `CHANGELOG.md`（intro）、`README.md` / `README.ja.md`（Versioning 節）、`docs/decisions/README.md`（ADR 索引）

### 下流 PJ
- P1 単独では影響なし（リリース側の変更のみ）
- P2/P3 実装後に `/inventory` / `/close-chat` の挙動が変わり、取り込み体験が改善される

### 既存リリース v0.5.0
- 遡及適用はしない（タイトルに prefix なし = Standard 扱いで運用）
- 次回リリース v0.5.1 以降から新フォーマット適用

## 関連

- ADR-0001: 配信方式（/inventory + GitHub Releases）
- ADR-0005: 下流統合設計原則
- ADR-0008: auto-memory 一本化（スキップ記録の基盤）
