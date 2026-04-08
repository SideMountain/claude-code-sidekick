# MCP サーバー推奨ガイド

「多く入れるほど良い」ではない。毎日使う 4-5 個に厳選する。
設定するだけでコンテキストを消費するため、使わない MCP は無効化する。

---

## 推奨 MCP サーバー

### Tier 1: ほぼ全PJで有効

| MCP | 用途 | インストール |
|-----|------|------------|
| **Playwright** | ブラウザテスト・E2E。トークン消費が最も少ない（~13.7k） | `claude mcp add playwright -s user -- npx @playwright/mcp@latest` |

### Tier 2: 状況に応じて追加

| MCP | 用途 | いつ使う |
|-----|------|---------|
| **Context7** | 最新ライブラリドキュメント取得。API の幻覚を防ぐ | 新しいフレームワークを導入する際 |
| **DeepWiki** | GitHub リポジトリのドキュメント構造化抽出 | OSS ライブラリの内部実装を調査する際 |
| **Sentry** | エラー監視・Issue 分析 | Sentry を使っている PJ |
| **Chrome DevTools** | パフォーマンス・ネットワークデバッグ | Core Web Vitals の最適化時 |

### Tier 3: 外部DB連携（NOTION_ENABLED=true の場合）

| MCP | 用途 | いつ使う |
|-----|------|---------|
| **Notion** | タスク管理・設計書連携 | 非エンジニアとのタスク共有、設計書の SoT を Notion に置く PJ |

---

## 設定方法

### ユーザーレベル（全PJ共通）

```bash
# Playwright（推奨: ユーザーレベル）
claude mcp add playwright -s user -- npx @playwright/mcp@latest

# Context7（推奨: ユーザーレベル）
claude mcp add context7 -s user -- npx @anthropic-ai/context7-mcp@latest
```

### プロジェクトレベル（PJ固有）

`.mcp.json` に記載。チーム共有される。

```json
{
  "mcpServers": {
    "sentry": {
      "command": "npx",
      "args": ["@sentry/mcp-server@latest"],
      "env": { "SENTRY_AUTH_TOKEN": "${SENTRY_AUTH_TOKEN}" }
    }
  }
}
```

**注意**: API キーは `.mcp.json` に直書きせず、環境変数で渡す。

---

## `/setup` での案内

`/setup` Step 2 のオプション項目で MCP の利用有無を確認し、
該当する Tier のインストールコマンドを案内する。

---

## アンチパターン

- 15 個以上の MCP を一度に有効にする（コンテキスト圧迫）
- 「念のため」で使わない MCP を残す
- プロジェクトレベルの `.mcp.json` にシークレットを直書きする
