# /auto-implement 完了レポート — few-shot 実例

> SKILL.md Phase 5e から参照。常駐させず、レポート生成時のみ読む（診断 #6・分類 E: few-shot として優秀だが常駐が問題）。
> ゴール: 朝起きて5秒で「何が起きたか」を判断でき、PR を開かずに次アクションを決められる詳細を含める。

## 単一タスクの場合

```
=== /auto-implement 完了レポート ===

[結果] 成功 ✅
[Issue] #42 — ユーザー認証機能の追加
[PR] #43 → release/stg（https://github.com/.../pull/43）
[ブランチ] feature/auto-20260408-auth

── 完了条件（/goal 宣言）──
  ✅ npx vitest run auth → 全パス
  ✅ /login で認証後にダッシュボードへ遷移（/verify で実証）

── 実装内容 ──
  変更: 8ファイル（+342, -28）
  主な変更:
    - app/api/auth/route.ts（新規: NextAuth エンドポイント）
    - lib/auth.ts（新規: セッション管理）
    - prisma/schema.prisma（User に role カラム追加）
    - components/LoginForm.tsx（新規: ログインUI）
  アプローチ: NextAuth + Prisma Adapter。ADR-0005 の方針に準拠。

── 検証（/verify）──
  スコープテスト: 12 passed, 0 failed
  全テスト: 156 passed, 0 failed / 型チェック: OK / ビルド: OK
  動作実証: /login → 認証 → /dashboard 遷移を確認

── レビュー結果（/review アダプタ）──
  [fitness]     決定的検出: なし
  [code-review] 公式レビュー: WARN 1（エラー時のログ出力が不足）
  [PJ規範]      REVIEW.md §1: 整合（Expand-Contract 準拠・HARD 抵触なし）
  最終判定: min()=2（WARN → 修正後 PR 作成可）
  修正ループ: 1回（Ops WARN → ログ追加で解消・/review verdict をそのまま採用）

── 難所裁定（R2/R3）──
  該当なし（trivial-gating R8 は NO=通常ゲート・矛盾 findings なし）

── budget-gate ──
  NORMAL（縮退なし）

── 知識還流（自動記録済み）──
  1. [PJ 固有] NextAuth の session callback で role を含める必要あり → feedback 候補

── バックログ追加（MEMORY.md に追記済み）──
  1. lib/auth.ts の token 生成ロジック共通化（INFO 指摘）
  2. LoginForm の E2E テスト追加（カバレッジ不足）

── 次のアクション ──
  → PR #43 をレビュー・マージしてください
==========================================================
```

## 並列実行の場合（/batch）

```
=== /auto-implement 完了レポート（並列3件・/batch）===

[全体結果] 2件成功 ✅ / 1件停止 🛑
[budget-gate] THROTTLE（five_hour 72%）→ fan-out 3→2 に縮退・ledger に記録

── Issue #10: ユーザー認証機能 ── ✅ 成功
  [PR] #43 → release/stg / 変更: 8ファイル（+342, -28）
  検証: 156 passed / レビュー: min()=2（Ops WARN 1 → 修正済み）
  知識還流: 1件 / バックログ: 2件

── Issue #11: メール通知テンプレ ── ✅ 成功
  [PR] #44 → release/stg / 変更: 4ファイル（+89, -12）
  検証: 160 passed / レビュー: min()=3（指摘なし）
  知識還流: 0件 / バックログ: 0件

── Issue #12: 管理画面ダッシュボード ── 🛑 停止
  [停止Phase] Phase 3（レビュー裁定）
  [停止理由] BLOCKER: N+1クエリ（code-review C1・min()=1）。
    lib/dashboard.ts L45 で User.findMany 内で Order を個別取得。
    include による一括取得に設計変更が必要（R2 設計判断 = 難所・敵対検証で確定）。
  [進捗] 実装完了 → 検証OK → レビューでブロック
  [ブランチ] feature/auto-20260408-dashboard（push済み、PR未作成）
  [再開方法] N+1 を修正後、以下で再開:
    cd ../my-project-auto-dashboard → N+1 修正 → /review → PR作成

── 知識還流（全タスク統合）──
  1. [PJ 固有] NextAuth session callback で role を含める必要あり
  2. [PJ 固有] ダッシュボードの集計クエリは include で一括取得すべき

── バックログ追加 ──
  1. lib/auth.ts token 生成共通化
  2. LoginForm E2E テスト追加
  3. ダッシュボード N+1 修正（Issue #12 のブロッカー）

── ledger 縮退記録（silent drop 禁止）──
  THROTTLE により Issue #12 の敵対検証 votes を 3→2 に縮退（正しさは削らず幅のみ）。

── 次のアクション ──
  → PR #43, #44 をレビュー・マージ
  → Issue #12 は N+1 修正が必要。対話モードで修正するか、
    修正方針を決めて再度 /auto-implement #12 で実行
==========================================================
```

## 入口ゲートで停止した場合（R1 NG）

```
=== /auto-implement 完了レポート ===

[結果] 停止 🛑
[Issue] #15 — 決済フロー実装
[停止Phase] Phase 0（入口ゲート R1）
[停止理由] R1 rubric で NG 3 件（1つでも NG→停止）:
  Q2 未決定マーカー: 本文に「Stripe vs PAY.JP（要検討）」が残存
  Q3 完了条件: 観測可能な完了条件（コマンド/テスト/画面）の言及なし
  Q4 曖昧語: 「失敗時はいい感じにリトライ」

[実行済み] なし（Phase 0 で停止のため実装未着手）
[消費リソース] 最小（入口ゲート判定のみ）

── 次のアクション ──
  → 上記3点を壁打ちで確定 → ADR に記録
  → 確定後に /auto-implement #15 で再実行
==========================================================
```
