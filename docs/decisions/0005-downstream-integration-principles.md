# ADR-0005: 下流統合設計原則

## ステータス

採用（2026-04-09）

## 背景

既存の本番稼働プロダクト（Next.js + Prisma 構成）が sidekick v0.3.0 を取り込む過程で、以下の問題が発生した:

1. sidekick のメタファイル（VERSION, CHANGELOG.md）がプロジェクトルートを汚染する
2. `*.example` ファイルが既存PJにはノイズになる
3. `.github/` テンプレートが下流PJ固有の文脈と競合する
4. `/setup` が既存PJ統合シナリオをカバーしていない
5. `.gitignore` パターンが `/setup` の配置結果と連動していない
6. `rules/` に毎セッション読み込む必要のないドキュメントが常駐している

OSS ベストプラクティスの調査結果（Husky/ESLint パターン: 1 config file + 1-2 dotdirs）とも整合させる。

## 検討内容

### ルートフットプリントの最小化

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| 現状維持 | 変更不要 | 下流PJから汚染の指摘 |
| **CLAUDE.md + .claude/ のみ** | OSS 慣行と整合。最小フットプリント | ファイル移動の手間 |
| 全て .claude/ に封じ込め | 最もクリーン | CLAUDE.md はルートにある方が自然 |

### バージョン管理方式

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| ルートに VERSION ファイル | シンプル | 下流PJを汚染 |
| .claude/VERSION | 汚染回避 | 非標準 |
| **git tag + GitHub Releases** | OSS 標準。下流にファイル残さない | ネットワーク必要 |

### テンプレート配置方式

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| ルートに *.example | 見つけやすい | 既存PJで競合・ノイズ |
| **`.claude/templates/` + /setup が opt-in で配置** | 既存PJ非侵襲 | /setup 実行が必要 |

## 決定

### 4つの設計原則

1. **`.claude/` 封じ込め** — sidekick のランタイム・メタデータ・テンプレートは全て `.claude/` 配下に格納する。プロジェクトルートに sidekick 固有のファイルを直接置かない
2. **ルートは `/setup` の成果物** — プロジェクトルートに配置するファイル（MEMORY.md, CLAUDE.local.md 等）は `/setup` が対話的に生成する。sidekick が直接配置しない
3. **既存PJ非侵襲** — 既存ファイルの上書き・競合を起こさない。opt-in で追加のみ。`/setup` に新規/既存の2モードを持たせる
4. **背景知識不要** — 下流PJが sidekick の内部設計を知らなくても、`/setup` の対話だけで正しい構成に到達できる

### 具体的な変更

- VERSION ファイル → git tag + GitHub Releases
- `*.example` → `.claude/templates/`
- `.github/` テンプレート → upstream 維持 + 下流向けは `.claude/templates/github/`
- `skill-agent-design.md` → `.claude/docs/`（コンテキスト常駐の解消）
- `mcp-recommendations.md` → `skills/setup/references/`（/setup 時のみ参照）
- `.gitignore` パターン → `/setup` が配置状況に応じて追記

## 理由

- Husky/ESLint の「1 config file + 1 dotdir」パターンが OSS の標準慣行
- 下流PJが増えるほど「非侵襲」の価値が上がる。初回は手間が増えても長期的にスケールする
- `rules/` に置くとコンテキストに常駐するが、スキル設計ガイドや MCP 推奨は毎セッション不要。適切な配置で ~400行 のコンテキストを節約

## 影響

- `/setup` が大幅改修（新規/既存2モード）
- `/inventory` のバージョンチェックが GitHub Releases API を使用
- 下流PJの理想的なルートフットプリント: `CLAUDE.md` + `.claude/` のみ
- ADR-0001 を改訂（VERSION ファイル廃止を反映）