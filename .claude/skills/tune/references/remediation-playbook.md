# 是正プレイブック（Step 4）

レポートでユーザーが選んだ是正を、安全に実装→PR する手順。**監査と違い、ここはコードを変更する** → HARD ルール（worktree / push・PR 確認 / コミット本文）を厳守。

---

## 0. 前提確認（業務リポは特に）

```bash
git -C <PJ> branch --show-current      # STG_ENABLED の判定材料
git -C <PJ> remote -v                  # origin の owner（gh アカウント切替の要否）
git -C <PJ> status --short             # 未コミット変更（触らない・worktree はクリーン base から切る）
gh api user --jq .login                # 対象 owner と一致するか。違えば gh auth switch
```

- **gh アカウント**: 対象リポの owner に合わせて `gh auth switch -u <user>`（PR 操作前）。
- **未コミット変更**: ユーザーの管轄。触らない。worktree は `origin/<base>` のクリーン状態から切る。

## 1. worktree 作成（H12/H13）

```bash
git -C <PJ> fetch origin
git -C <PJ> worktree add <別パス>-tune -b feature/<用途> origin/<base>
```

- **base**: STG_ENABLED=true なら `release/stg`、false なら `main`。PR 経路を間違えない（feature→main 直は STG では禁止）。
- worktree は作業ディレクトリ内のパスに作る（`/add-dir` 済みの場所）。**軽量パターン**（config のみ変更ならランタイム不要・deps install 不要）。
- H13: auto-memory の Active Work に記録。

## 2. バッチ設計（純利益から）

| バッチ | 中身 | PR 方針 |
|---|---|---|
| **純利益（gated=false）** | 設定/CI のみ・テスト不変 | **まとめて 1 PR** 可。低リスク |
| **要ゲート（gated=true）** | コード/テスト変更 | **1件ずつ**・green 確認・人手OK |

純利益でも「分が増える」施策（shard 等）は PR 本文に cost↔time を明記。

## 3. ローカル検証（CI が回せない時の confidence）

実 CI が最終証拠だが、回せない/回す前に静的検証で confidence を上げる:

- **ワークフロー**: `actionlint`（式・job依存・matrix・action入力を検査。YAML パースより深い）。gh で公式バイナリ取得可。
- **vitest 分割**: `pnpm exec vitest list --shard=1/4`（**非実行**でテスト収集・分割を確認）。node_modules のあるメイン checkout で。
- **YAML 構文**: `python3 -c "import yaml; yaml.safe_load(open(f))"`。
- **限界の明示**: ランナー固有のランタイム挙動（cache hit/miss・matrix 実展開・スイート green）はローカル不可 → 「最終証拠は CI」と正直に言う。

## 4. コミット（H15）

本文に **背景 / 対応 / 影響** を必ず記載。

```
<type>: <要約>

背景: （なぜ必要か。監査の発見を1-2行で）
対応: （何をしたか。純利益/要ゲートの別、テスト不変の明記）
影響: （変更ファイル。テスト/プロダクトコード不変なら明記）

Co-Authored-By: ...
```

公開リポでは固有名詞・接続先・同期元参照を含めない（`oss-doc-authoring.md`）。

## 5. push / PR（H7/H8 — 必ず確認）

- push・PR 作成は**ユーザー確認後**。「何を承認するのか」を明記（ソース→ターゲット + 変更概要 + 対象環境）。
- PR 本文に「期待効果（推定）」「⚠ マージ時の必要作業」「実測は CI で確認」を入れる。

---

## よくある落とし穴（実戦由来）

- **CI ジョブ分割でブランチ保護が壊れる**: 単一ジョブ名（例 `Lint / Test / Build`）を required check にしている場合、分割すると旧名のチェックが消え **全 PR が Expected で詰まる**。→ **安定名の集約ゲート `CI Success`**（`if: always()` + `needs.*.result` 厳密検査）を追加し、required check をそれ1本に張替（admin 作業＝ユーザー）。
- **`npm ci` の lockfile drift**: `npm install` 運用だった repo は初回 `npm ci` で peer 不一致が露見しうる → その場合 lockfile 再生成 PR を先行。CI green がそのまま lockfile 健全の証明。
- **GitHub Actions 課金停止**: org の spending-limit で全 run が startup_failure（`steps: []`・注釈に "spending limit"）。**自分の変更起因と誤認しない** — base も赤なら課金問題。Claude/Anthropic 課金とは無関係の別ベンダー。
- **pre-push hook が WSL で hang/fail**: config のみ変更でテストロジック不変なら `--no-verify` 可（環境依存の回避策 — 環境により不要。CI が検証）。業務リポでは安易に多用しない。
- **マージ判断は「効果」でなく「安全」**: green CI = 安全確認。効果（速度）の大小はマージ後に自動で乗る。未検証（CI 未通過）のものは業務リリースブランチに入れない。
- **PR を開いたまま待つドリフト**: base が進んでも、触るファイルが被らなければクリーンなまま。再開時に base 取り込み→green→マージ。作業は remote ブランチに永続。

---

## ライフサイクル

- worktree はユーザーが「完了」と言うまで保持（PR マージ後すぐ消さない）。
- マージ後: Active Work を「確認待ち」に。ユーザー明言後に `worktree remove` + ブランチ整理 + Active Work 更新。
