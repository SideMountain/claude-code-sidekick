# ADR-0003: Slack連携 + cron実行のアーキテクチャ

## ステータス

承認済み（2026-04-07）

## 背景

以下の要件を満たすアーキテクチャが必要:
1. 非エンジニアメンバーが気軽にタスク依頼できる
2. オーナーが外出中でも開発が自律的に進む
3. PJ数が増えてもコストがスケールしない（固定費で収まる）
4. 悪意ある依頼・破壊的依頼を確実にブロックする
5. 各PJのハーネス（CLAUDE.md, hooks, rules）が正しく適用される

## 検討内容

### 実行環境

| 選択肢 | サブスク内 | 自動トリガー | コスト |
|--------|-----------|------------|--------|
| Claude Code CLI（手動） | ○ | × | $0 |
| **Claude Code CLI + cron（PC上）** | **○** | **○** | **$0** |
| VPS + Claude Code | ○ | ○ | $5-10/月 |
| GitHub Actions + Claude API | × | ○ | $30-60/月（PJ比例） |
| Claude Code SDK | × | ○ | API従量 |

### Issue起票の入口

| 選択肢 | 心理的ハードル | 対話 | 技術力要件 |
|--------|-------------|------|----------|
| GitHub Issue直接 | 高い | 非同期 | GitHub必要 |
| Claude Code CLI | 中 | リアルタイム | CLI操作必要 |
| **Slack** | **低い** | **リアルタイム** | **不要** |

### セキュリティ

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| パターンマッチのみ | 高速 | 誤検知・検知漏れ |
| Claude判断のみ | 柔軟 | 判断ミスのリスク |
| **2層（コマンド→パターンマッチ、Issue→Claude判断）** | 適材適所 | 設計が複雑 |

## 決定

### 1. 実行環境: オーナーのPC + Claude Code CLI + cron

```
コスト:
  Claude Max: $100/月（既存・変更なし）
  追加コスト: $0
  PJ数に関係なく固定
```

GitHub Actionsは「AI不要な自動化」のみ（CI/CD、Playwright、Slack通知、ラベル自動付与）。Claude APIは呼ばない。

### 2. Slack連携: Slack App（ローカル常駐）+ リアクション分岐

```
Slack App（オーナーのPC上で常駐）
  ↓ リアクション検知
  :issue:   → 機能要求 → Issue起票フロー
  :bug:     → バグ報告 → Issue起票フロー（bugfixテンプレ）
  :idea:    → アイデア → Tasks DB投入（すぐ実装しない）
  :hotfix:  → 緊急修正 → P0で起票
  :question: → 質問 → Claude Codeが回答するだけ（Issue化しない）

チャンネル → リポジトリ対応:
  設定ファイルで管理。不明な場合は聞き返す。
```

各PJのディレクトリで Claude Code を起動するため、各PJのハーネスが自動適用される。

### 3. cron設定

```
1時間おき（09:00-20:00 JST）:
  各PJの approved Issue をスキャン
  → あれば [implementing] にラベル変更 → 実装 → PR
  → ロック付き1件ずつ順次実行

毎朝 09:00:
  全PJの /inventory 実行

毎日 19:00:
  日次サマリ → Slack通知

毎週月曜 10:00:
  /scout 実行 → レポート → Slack通知
```

新規タスク着手は ACTIVE_HOURS（09:00-20:00 JST）内のみ。実行中のタスクは完了まで続行。

### 4. セキュリティ: 2層ガード

```
Layer 1: コマンドレベル（既存hooks。パターンマッチ）
  → rm -rf, DROP TABLE, force push 等を物理ブロック

Layer 2: Issueレベル（Claude Codeの判断）
  → 「この要件は認証/データ/インフラに触れるか？」
  → 触れる場合 → [needs-security-review] ラベル → オーナー承認必須

Layer 3: レビューレベル（/review のセキュリティ観点）
  → OWASP Top 10、認証バイパス、データ漏洩チェック
```

### 5. ラベルリレー

```
Issue: [triage] → [approved] → [implementing] → [needs-review]
PR:   [needs-review] → [stg-ready] → [prd-ready] → [prd-approved]
例外: [blocked]（セキュリティ）, [needs-clarification]（明確化必要）
      [needs-fix]（修正必要）, [needs-security-review]（オーナー承認必須）
```

### 6. 二重実行防止

- ラベル制御: [approved] → [implementing] に即変更で他のcronが拾わない
- ロックファイル: 実行中は .claude-cron-lock を作成

## 理由

- サブスク内完結はPJスケールのためのコスト判断。API従量はPJ増加に比例して破綻する
- Slackは非エンジニアの起票ハードルを最小化する唯一の手段
- 各PJのディレクトリでClaude Codeを起動する方式は、ハーネスの独立性を保証する
- セキュリティの2層分離は、パターンマッチの誤検知問題とClaude判断の併用で解決
- 夜間停止は「新規着手しない」であり「実行中を中断しない」

## 影響

- 新規: Slack App のローカル常駐プロセス
- 新規: cron / タスクスケジューラ設定
- 新規: チャンネル → リポジトリ対応表の設定ファイル
- 新規: ラベル定義 + GitHub Actions テンプレート（CI/CD、Playwright、通知）
- 新規: Issue テンプレート（機能要求、バグ報告）
- 変更: /inventory にGitHub Issues取得ステップを追加
- 将来: PC運用で不便を感じたらVPSに移行を再検討
