---
paths:
  - docs/**
  - README*
  - CHANGELOG.md
  - LICENSE
  - brain/**
  - .claude/rules/**
  - .claude/skills/**
  - .github/**
---

# 個人情報・固有名詞の混入禁止（HARD グレード）

public な git リポ（OSS 含む）の**公開ファイル**に、特定の個人・組織・接続先を識別できる情報を残してはならない。記録は auto-memory（git 非追跡）に退避する。

## 対象ファイル

`auto-memory/` `MEMORY.md` `CLAUDE.local.md` `settings.local.json` `.data/` 以外の git 追跡ファイル全て。特に注意:

- ADR (`docs/decisions/`)
- `README*`、`CHANGELOG.md`、`LICENSE`
- `brain/**`、`.claude/rules/**`、`.claude/skills/**`、`.github/**`
- アプリケーションコード（コメント・テストデータも含む）

## 禁止パターン

| カテゴリ | 該当例 | 代替表現 |
|---|---|---|
| Notion ID / URL | `notion.so/<32桁hex>`、ハイフン付き UUID、`[0-9a-f]{32}` リテラル | `Project Configuration の <ENV_VAR> で設定` |
| 内部 URL | `slack.com/...`、`docs.google.com/...`、社内 Wiki | 機能名・手順説明に置換 |
| 個人 PJ / リポ名 | sidekick / claude-code-sidekick 以外の自分のリポ名 | `別リポ` `業務系 PJ` 等の汎用表現 |
| 個人名 / メール | 個人 GitHub ID（OSS の組織名は除く）、メールアドレス | 削除 or 役割表現 |
| 接続情報 | DB 接続文字列、API キー、Notion DB ID、Slack channel ID | 環境変数名・Project Configuration 参照 |
| 企業・組織名 | 自社・取引先名 | 役割表現（例: 「業務 PJ」「外部 SaaS」） |

**例外**: OSS 配布物として参照する自リポの GitHub 組織名（例: `gh api repos/<OWNER>/<REPO>/...` の機能上の参照）は OK。

## セルフレビュー: PII スキャン

公開ファイルを変更したら、commit 前に以下を実行する。

```bash
# 引数指定スキャン。検出ゼロなら出力なし & exit 0
scan_pii() {
  local files=("$@")
  [ ${#files[@]} -eq 0 ] && return 0
  local found=0
  local hits

  hits=$(grep -nE '[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|notion\.so/[0-9a-f]{8}' "${files[@]}" 2>/dev/null) \
    && { echo "=== Notion UUID / URL ==="; echo "$hits"; found=1; } || true

  hits=$(grep -nE 'slack\.com/[a-zA-Z0-9]|docs\.google\.com/[a-zA-Z0-9]|drive\.google\.com/[a-zA-Z0-9]' "${files[@]}" 2>/dev/null) \
    && { echo "=== 内部 URL ==="; echo "$hits"; found=1; } || true

  hits=$(grep -nE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "${files[@]}" 2>/dev/null \
    | grep -v -E 'noreply@|example\.(com|org|net)|@anthropic\.com') \
    && { echo "=== email ==="; echo "$hits"; found=1; } || true

  # 個人 PJ 名は PJ ごとにカスタマイズ。例:
  # hits=$(grep -inE 'legacy-app|internal-batch' "${files[@]}" 2>/dev/null) \
  #   && { echo "=== PJ name ==="; echo "$hits"; found=1; } || true

  return 0
}

# ステージ済みの公開ファイルをまとめてスキャン（ヘルパー）
scan_staged_public() {
  local targets
  targets=$(git diff --cached --name-only --diff-filter=AM | \
    grep -E '^(docs/|README|CHANGELOG|LICENSE|brain/|\.claude/rules/|\.claude/skills/|\.github/)' | \
    grep -v -E '(MEMORY\.md|CLAUDE\.local\.md|settings\.local\.json|\.data/|agent-memory-local/)')
  [ -n "$targets" ] && scan_pii $targets || echo "(対象ファイルなし)"
}
```

**正規表現の厳格化**: `slack.com/<char>` 形式（実 URL）のみマッチさせ、`slack.com/...` のような placeholder はスキップする。pii-prevention.md 自身の例示記述で誤検知しないようにするための工夫。

**メールフィルタ**: `noreply@`、`example.com|org|net`、`@anthropic.com`（Claude Code 自動付与の Co-Authored-By 用）は除外する。

**該当が見つかった場合**: 該当箇所を汎用表現に置換してから commit する。判断に迷う固有名詞はユーザーに確認する。検出ゼロ（出力空）が通過条件。

## 判断基準

「この情報は OSS を fork した第三者にとって意味があるか?」

- **YES** → 残してよい（公開組織名、機能名、業界共通の概念）
- **NO** → 汎用表現に置換、または auto-memory に退避

## 自動実行ポイント

仕組み化の3層でいう **認知**（スキルが scan する）と **強制**（commit を物理ブロックする）を両立させる。

| タイミング | レイヤー | 実行主体 | 対象 |
|---|---|---|---|
| ADR ドラフト完成後 | 認知 | `/record-decision` | 当該 ADR ファイル |
| セッション終了時 | 認知 | `/close-chat` | ステージ済み + 未ステージの公開ファイル |
| PR 作成前 | 認知 | `/review` | 変更ファイル全件 |
| **commit 時** | **強制** | **`.claude/githooks/pre-commit`** | **staged な公開ファイル（検出時は commit を中止）** |

スキル（認知層）が `scan_pii` を呼び出し、pre-commit hook（強制層）が最終ゲートとして commit を物理ブロックする。
hook は `/setup` が `core.hooksPath` を設定して有効化する（clone ごと、`git config core.hooksPath .claude/githooks`）。
PJ 固有の人名・PJ名・接続先は scan_pii のコメント例と hook 末尾の両方でカスタマイズする。
