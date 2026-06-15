---
name: review
description: "統合レビュー（オーケストレーター）。4観点（code/test/ops + プロジェクト固有）を並列実行し、結果を統合して総合判定する。"
user-invocable: true
allowed-tools: "Read Grep Bash(git *) Agent"
---

# 統合レビュー（/review）

## 目的

4つの専門レビュー観点を並列実行し、結果を統合して総合判定を行う。
コミット前またはPR作成前に実行する。

## 6つの観点

| スキル | 主管 | フォーカス |
|---|---|---|
| `/review-code` | コード品質・整合性・DB設計・水平展開 | 全パスの実装漏れ検出 |
| `/review-test` | テスト網羅性・品質・モック正確性 | テストケースの十分性 |
| `/review-ops` | 障害モード・可観測性・コスト・ロールバック | 運用時の安全性 |
| `/review-design` | UI/UX一貫性・デザインシステム・a11y | フロントエンド品質 |
| `/review-spec` | API契約・仕様書乖離・破壊的変更 | 仕様の整合性 |
| *(プロジェクト固有)* | ドメイン固有チェック | CLAUDE.md に定義 |

> **Note:** プロジェクト固有の不変条件（ビジネスルール違反の防止条件）は CLAUDE.md に定義する。
> 不変条件が定義されている場合、各観点でその実装・テスト・検知の有無を確認する。

## 手順

### Step 1: 変更内容の把握

```bash
# ベースブランチを自動取得
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@')
# CLAUDE.md の STG_ENABLED に応じて上書き（下記ロジック参照）

# 変更ファイル一覧
git diff $BASE_BRANCH...HEAD --name-only

# 変更の統計
git diff $BASE_BRANCH...HEAD --stat

# コミット一覧
git log $BASE_BRANCH...HEAD --oneline
```

> **BASE_BRANCH の判定ロジック:**
> 1. `git symbolic-ref refs/remotes/origin/HEAD` でリポジトリのデフォルトブランチを取得（一次ソース）
> 2. CLAUDE.md の `STG_ENABLED` を確認し、必要に応じて上書き:
>    - `STG_ENABLED=true` かつ現在のブランチが `feature/*` → `origin/release/stg`
>    - `STG_ENABLED=true` かつ現在のブランチが `release/stg` → `origin/main`
>    - `STG_ENABLED=false` → symbolic-ref の結果をそのまま使用

### Step 1.5: 変更スコープ判定（動的スキップ）

変更ファイルの種類から、実行する観点を自動決定する。**全観点を毎回通す必要はない。**

| 変更スコープ | 実行する観点 | スキップする観点 |
|---|---|---|
| `.claude/`, `docs/`, `CLAUDE.md`, `MEMORY.md` のみ | code | test, ops, design, spec |
| `__tests__/` のみ（テストファイルだけの変更） | test | code, ops, design, spec |
| `*.tsx`, `*.jsx`, `*.css` 等の UI コンポーネント | code, test, **design** | ops, spec |
| `app/api/`, `route.ts`, `prisma/schema.prisma` 等の API/DB | code, test, ops, **spec** | design |
| DB スキーマ・マイグレーションを含む | code, **ops 必須**, **spec 必須** | design |
| 上記の複合 | 和集合（全ての該当観点を実行） | — |

**判定ルール:**
- 変更ファイル一覧を上記テーブルで照合し、実行観点を決定する
- 複数スコープに該当する場合は**和集合**（全ての該当観点を実行）
- スキップする観点は「対象なし — スキップ」と明示して報告する
- ユーザーが `/review` 実行時に「全観点で」と指定した場合はスキップせず全実行する
- プロジェクト固有の観点（UI/デザイン等）がある場合は、CLAUDE.md の定義に従って追加判定する
- 変更が `skills/` を含む場合、`.claude/docs/skill-agent-design.md` を事前に読み込み、Return Contract・コンテキスト隔離の基準を踏まえてレビューする

### Step 2: 観点の並列レビュー

Agent ツールで Step 1.5 で決定した観点を**並列実行**する。

Agent の起動方法・テンプレート・渡すパラメータは `agents/review-agent-template.md` を参照。

### Step 3: 結果統合

レビュー結果を統合し、以下を出力する。

#### 3a. 観点間の矛盾チェック

- code と test で異なる判断をしていないか
- test が仕様の受入条件を網羅しているか
- ops の指摘が code の実装に反映されているか

#### 3b. 不変条件の横断サマリ（CLAUDE.md に不変条件が定義されている場合）

各観点の不変条件チェック結果を統合:

```
=== 不変条件 横断チェック ===
{条件名}:
  code: 全パス実装済み / 漏れ: [パス名]
  test: 違反テストあり / 不足: [ケース名]
  ops:  検知可能 / 不可: [理由]
```

#### 3c. 設計書影響チェック（NOTION_ENABLED=true の場合）

コード変更が設計書に影響するか確認する。
CLAUDE.md または `.claude/rules/notion.md` に定義された対応表に基づき、
変更パターンから影響する設計書を特定する。

該当する設計書がある場合、更新を提案する。

### Step 4: 総合判定の出力

```
=== 統合レビュー結果 ===

[Code]    コミット可 / 修正必要 / ユーザー確認必要
[Test]    テストOK / テスト追加必要 / テスト修正必要
[Ops]     運用OK / 要対応 / ユーザー確認必要
[Design]  UI OK / 指摘あり / 対象外（スキップ）
[Spec]    仕様OK / 指摘あり / 対象外（スキップ）

[不変条件] 全条件クリア / 漏れあり / 対象外（不変条件未定義）
[設計書影響] なし / 要更新 / 対象外（Notion未連携）
[観点間矛盾] なし / あり（詳細）

===========================
最終判定: PR作成可 / 修正後に再レビュー / ブロッカーあり
===========================

指摘事項サマリ:
  [BLOCKER] ブロッカー（PR作成前に必ず修正）:
    - ...
  [WARN] 推奨改善（今回 or 次回で対応）:
    - ...
  [INFO] 提案（任意）:
    - ...
```

> **静的 → 動的の橋渡し**: 上記は静的レビュー。`PR作成可` でも挙動に不安があれば、公式 `/verify` でアプリを実際に動かして確認する（下記「公式 bundled スキルとの使い分け」参照）。

## 個別実行

各観点は個別に実行することもできる:
- `/review-code` — コミット前の実装チェック
- `/review-test` — テスト追加後の品質確認
- `/review-ops` — デプロイ前の運用確認
- `/review-design` — UI変更後のデザイン一貫性確認
- `/review-spec` — API変更後の仕様整合性確認

## 公式 bundled スキルとの使い分け

`/review` は **ccs 統合オーケストレーター**（6観点・CLAUDE.md 不変条件・動的スキップ・PJ 文脈込み）。Claude Code 公式 bundled の単機能スキルとは目的が異なるため、置き換えではなく**補完的に**使う:

| 公式スキル | 役割 | `/review` との関係 |
|---|---|---|
| `/code-review` | diff にフォーカスした correctness バグ + reuse/simplify 検出（low〜ultra の effort 段階、cloud 隔離も可） | `/review` の code 観点の高速スポット版。PR 直前の追加パスとして併用可 |
| `/simplify` | 変更コードの reuse/簡潔化/効率の cleanup（品質のみ、バグは探さない） | `/review-code` 指摘後の整形に。バグ検出は `/review` 側 |
| `/verify` | アプリを実際に動かして挙動を確認（テストでなく実挙動） | `/review`（静的）の後の動的確認 |
| `/security-review` | セキュリティ専用の深掘りパス | `/review-code` が `[needs-security-review]` を出したら委譲 |

**原則**: PR 前ゲートは `/review`（統合）を主とし、公式 bundled は「特定観点を深掘りするスポット」として重ねる。**新スキルは作らず、公式を呼び分ける**（ADR-0018 の最小ループ — 能動面を増やさず配管で吸収）。

## Gotchas

- **Step 1.5 の誤スキップ** — 変更スコープ判定で `.claude/` 変更のみ → code のみと判定するが、スキル定義の変更がレビューロジック自体に影響する場合がある。変更ファイルが `skills/review*/` を含む場合は全観点実行を検討する
- **Agent 並列実行のコンテキスト汚染** — 各 Agent は独立したコンテキストで動作するが、同一 Worktree 内のファイルを読むため、レビュー中に別チャットがファイルを変更すると不整合が生じうる
- **Step 3a 矛盾チェックの見落とし** — code が「OK」、test が「テスト追加必要」の場合、実際には code 側にもテスト可能な設計への修正が必要な場合がある。単に test だけの問題と判断しない

## 注意事項

- 全ステップを実行すること（「問題なさそうだから省略」はしない）
- 指摘が見つかった場合、修正してから再度レビューする
- レビュー結果はユーザーに報告する（自分で判断して握りつぶさない）
- 不変条件リストは CLAUDE.md で継続的にメンテナンスする（新機能追加時に更新）