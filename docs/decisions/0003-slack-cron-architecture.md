# ADR-0003: 無人実行のアーキテクチャ（cron + Slack 連携）

## ステータス

採用（2026-04-07）

## 背景

sidekick を「寝ている間に Issue が PR になる」ツールにするには、以下を満たす実行基盤が必要:

1. オーナー不在でも開発が自律的に進む
2. プロジェクト数が増えてもコストがスケールしない（固定費で収まる）
3. 各プロジェクトのハーネス（CLAUDE.md, hooks, rules）が正しく適用される
4. 破壊的な操作を確実にブロックする

## 検討内容

### 実行環境

| 選択肢 | サブスク内 | 自動トリガー | 追加コスト |
|--------|-----------|------------|----------|
| Claude Code CLI（手動） | ○ | × | $0 |
| **Claude Code CLI + cron** | **○** | **○** | **$0** |
| VPS + Claude Code | ○ | ○ | $5-10/月 |
| GitHub Actions + Claude API | × | ○ | $30-60/月（PJ比例） |

### セキュリティ

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| パターンマッチのみ | 高速 | 誤検知・検知漏れ |
| Claude 判断のみ | 柔軟 | 判断ミスのリスク |
| **多層ガード** | 適材適所 | 設計が複雑 |

## 決定

### 1. 実行環境: ローカル PC + Claude Code CLI + cron

```
コスト:
  Claude Max: $100/月（既存サブスクリプション）
  追加コスト: $0
  PJ数に関係なく固定
```

各プロジェクトのディレクトリで Claude Code を起動するため、各PJのハーネスが自動適用される。GitHub Actions は「AI 不要な自動化」のみ（CI/CD、E2E テスト、通知）。

### 2. タスク入口: Slack → GitHub Issue（オプション）

```
Slack（オプション連携）:
  リアクションでタスク種別を分類 → GitHub Issue に自動起票
  非エンジニアメンバーが気軽にタスク依頼できる

GitHub Issue（標準）:
  Issue テンプレートで構造化された起票
  /auto-implement が Issue を自動実装
```

### 3. cron パターン（参考構成）

```
定期スキャン（業務時間内）:
  approved ラベルの Issue をスキャンし、自動実装を開始
  ロック付き1件ずつ順次実行（二重実行防止）

日次:
  /inventory 実行 → サマリ通知

週次:
  /weekly-inventory 実行 → レポート通知
```

### 4. セキュリティ: 多層ガード

```
Layer 1: コマンドレベル（hooks によるパターンマッチ）
  → rm -rf, DROP TABLE, force push 等を物理ブロック

Layer 2: Issue レベル（Claude Code の判断）
  → 認証・データ・インフラに触れる場合 → オーナー承認必須

Layer 3: レビューレベル（/review のセキュリティ観点）
  → OWASP Top 10、認証バイパス、データ漏洩チェック
```

### 5. ラベルリレー

```
Issue: [triage] → [approved] → [implementing] → [needs-review]
PR:   [needs-review] → [stg-ready] → [prd-ready] → [prd-approved]
例外: [blocked], [needs-clarification], [needs-fix], [needs-security-review]
```

## 理由

- サブスク内完結により PJ 数が増えてもコストが固定。API 従量課金は PJ 比例で破綻する
- 各PJディレクトリで Claude Code を起動する方式は、ハーネスの独立性を保証する
- セキュリティの多層分離は、パターンマッチの確実性と Claude 判断の柔軟性を両立する

## 影響

- `/auto-implement` スキルの追加（Phase 0-5 パイプライン）
- ラベル定義 + GitHub Issue テンプレートの追加
- `/inventory` に GitHub Issues 取得ステップを追加
- 詳細なセットアップ手順は [cron-setup-guide.md](../cron-setup-guide.md) を参照
