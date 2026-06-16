---
name: tune
description: "PJ健全性テコ入れ。テスト実行/CIの高速化・テスト棚卸し（削除せず統合/補強/格上げ）・コード共通化を read-only 監査→人手ゲートで是正する。長期/大規模PJの定期テコ入れ。"
user-invocable: true
allowed-tools: "Read Edit Write Grep Glob Bash(git *) Bash(gh *) Bash(wc *) Agent"
---

# /tune — PJ健全性テコ入れ（テスト高速化・棚卸し・コード共通化）

## 目的

コード+テストの健全性を定期的にテコ入れする。`/weekly-inventory` が「知識の棚卸し」なら、`/tune` は「**コード+テストの棚卸し+高速化**」。長期・大規模PJで肥大化したテスト/CI/ソースを、**安全網を一切減らさずに**健全化する。

**位置づけ**: `weekly-inventory` の兄弟（パターンD = 監査は隔離委譲・是正はメイン対話。`.claude/docs/skill-agent-design.md` §5-D）。
**実行タイミング**: 手動。テスト/CI が遅いと感じた時、肥大化が気になる時、定期メンテとして。

---

## 安全原則（HARD・着手前に必読）

**監査・是正に入る前に `references/safety-guardrails.md` を必ず読む。** 要点（違反は設計事故）:

- **テスト削除を提案しない** — 統合 / 補強 / 格上げ / quarantine / 追加 のみ
- **E2E / integration / regression は棚卸し対象外**
- **監査は read-only 静的**（テストスイート実行・ビルド・DB接続・`.env` 接触は一切しない）
- **gated 分離**: 純利益（設定のみ・破壊なし）↔ 要ゲート（worktree+PR+green+人手OK）。要ゲートは**夜間 auto-implement `--dangerouslySkipPermissions` ループ対象外**
- **mutation score / coverage% を削除根拠にしない**（不足箇所の発見＝追加用途のみ）
- **CI minutes を増やす施策（shard 等）は明示**し、cost↔time のトレードオフを出す

---

## 実行方式（パターンD）

Step 1-2 の監査は **Agent ツールで隔離実行**（メインコンテキスト保護・Return Contract）。Step 0/3/4 の検出・選択・是正はメインで対話する。`context: fork` が当環境で安定確認できたら宣言的隔離へ移行可（`skill-agent-design.md` §7）。

---

## 手順

### Step 0: 対象検出（メイン）

1. 対象PJのパスを確認（作業ディレクトリ外なら `/add-dir` を案内）。
2. スタック検出: `package.json`（test framework=vitest/jest/playwright、PM=npm/pnpm/yarn）or `pyproject.toml`（pytest）。CI=`.github/workflows/`。
3. 規模偵察（`references/audit-lanes.md` の偵察コマンド）: テストファイル数・E2E数・テストLOC・src LOC・CI workflow。
4. **read-only 宣言**: 以降テストスイート実行・ビルド・DB接続・`.env` 接触は行わない。

### Step 1: 4レーン監査（委譲・並列）

`references/audit-lanes.md` の4レーンプロンプトを Agent に**並列**で渡す（各 read-only 静的）:

| レーン | 観点 |
|---|---|
| ① テスト実行の高速化（最重要指標） | 直列実行・重い setup・並列化漏れ・巨大テストファイル・実IO混入 |
| ② CI高速化 | ジョブ並列化・キャッシュ・affected実行・install方式 |
| ③ テスト棚卸し（見直し・削除しない） | 真の重複・トートロジー/弱いアサート・実装結合の脆さ |
| ④ コード共通化・単純化 | バイト一致重複・巨大ファイル・高複雑度・コピペ足場 |

各レーンは構造化 findings を返す（schema は `references/audit-lanes.md`）。

### Step 2: 統合（委譲 or メイン）

findings を統合 → `references/safety-guardrails.md` を強制 → **優先度レポート**（高速化ファースト・gated 分離・横断トップN）。**削除提案ゼロ**を検証してから提示する。

### Step 3: レポート提示＋選択（メイン対話）

横断トップN + 純利益/要ゲート分離表を提示。cost↔time（CI minutes 影響）を明示。ユーザーが着手バッチを選択。**勝手に実装しない。**

### Step 4: 是正（メイン対話・要ゲート遵守）

`references/remediation-playbook.md` に従い worktree+PR で実装（純利益から）:

- **純利益（設定のみ）**: 1 PR にまとめてよい。テスト件数・内容・挙動を変えない。
- **要ゲート（コード/テスト変更）**: 1件ずつ green 確認＋人手OK。worktree+PR、夜間ループ対象外。
- **ローカル検証**: CI が回せない時は `actionlint`（ワークフロー）・`vitest list --shard`（分割確認）等で静的検証。
- **H7/H8 遵守**: push / PR 作成は必ずユーザー確認。

---

## Return Contract（Step 1-2 委譲分）

### 返すもの
- レーン別 findings（`title` / `severity` / `locations` / `evidence` / `suggestion` / `risk` / `gated`）
- 統合レポート（高速化ファースト・gated 分離・横断トップN・cost注記）
- Step 0 の規模偵察数値

### 返さないもの
- ファイルの全文・grep の生出力・監査の中間ログ・読んだ各ファイルの逐次ダンプ

### 出力フォーマット
`references/audit-lanes.md` の「レポート構成」（要約 / ①②③④ / 安全制約）に従う。

---

## Gotchas

- **監査は静的のみ**。スイート実行・ビルド・DB接続は read-only 違反。シグナルは grep 件数・ファイルサイズ・パターン密度で取る。
- **削除提案が1件でも出たら `safety-guardrails.md` 違反** → 統合/補強/格上げ に変換し直す。
- **「分が増える」施策（shard・ジョブ増）は課金状況を確認**。spending-limit に抵触している org では cost 優先（純利益＝分を減らす施策を先に）。
- **ccs 自体はテスト希薄** → 下流PJで dogfood する。対象が作業ディレクトリ外なら `/add-dir` が必要。
- **大規模PJはレーンを Agent で並列**しメインコンテキストを保護（全ファイルを読ませない。ホットスポットのみ）。
- **STG_ENABLED=true のPJ**は feature→release/stg。是正 PR の経路を間違えない（`remediation-playbook.md`）。
