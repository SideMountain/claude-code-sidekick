# ADR-0007: thinking.md を「入れ替え可能な思考OS」として位置づける

## ステータス

採用（2026-04-16）

## 背景

sidekick の差別化要素として「安全フック」が前面に出ているが、本当にユニークなのは **thinking.md による知識の複利効果**（feedback → 原則への昇格 → 思考OSの成長）である。

脳tion（Notion AI 向けの思考OS）との対比で、以下のギャップが明確になった:

- thinking.md が `rules/` 内にあり、他のルールファイルと同格に見えている
- CLAUDE.md §1「オーナーの判断軸」が空で、thinking.md へのリンクがない
- 「入れ替え可能な脳」というコンセプトが README にも CLAUDE.md にも表現されていない
- 成長サイクル（feedback → 昇格 → thinking.md 更新）が仕組みとして存在するが、認知されていない

## 検討内容

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| A: thinking.md を .claude/ 直下に昇格 | 「脳」として特別な位置づけが構造で伝わる。rules/ との目的分離が明確 | Claude Code が自動ロードしない（rules/ 外は対象外）。**不採用** |
| **B: rules/ に残し、冒頭説明 + CLAUDE.md §1 リンク + README で訴求（採用）** | 自動ロード保証。CLAUDE.md §1 で「脳」であることを宣言 | 構造上は rules/ の一つに見える（ドキュメントで補う） |
| C: CLAUDE.md に thinking.md の内容を統合 | ファイル数削減 | CLAUDE.md が肥大化。入れ替え可能性が失われる |

### セットアップ時の思考OSカスタマイズについて

| 選択肢 | メリット | デメリット |
|--------|---------|-----------|
| A: /setup で対話式にカスタマイズを強制 | 初期精度が高い | セットアップが重くなる。面倒で離脱する |
| **B: テンプレートのまま動かし、weekly-inventory で自然に育てる（採用）** | 導入が軽い。使いながら価値を実感 | 育つまで時間がかかる |
| C: session-start で毎回リマインド | 認知は確実 | ノイズになる |

## 決定

### 1. thinking.md の位置と役割

- `.claude/rules/thinking.md` に配置を維持（Claude Code の自動ロード対象であるため）
- ただし、冒頭の説明 + CLAUDE.md §1 からのリンクで「これはルールではなく思考OS」と明示する
- thinking.md = 「人」に紐づく判断軸（プロジェクトを跨いで持ち運べる）
- rules/*.md（thinking.md 以外） = プロジェクト固有のルール（コーディング規約、DB戦略等）
- **判断基準: 「プロジェクトを変えても持っていきたいか？」** → Yes なら thinking.md、No なら rules/

> 当初 `.claude/` 直下への移動を検討したが、Claude Code は `.claude/rules/*.md` のみ自動ロードし、
> `.claude/*.md`（CLAUDE.md/CLAUDE.local.md 以外）は対象外であることが判明。自動ロードを優先し rules/ に維持。

### 2. CLAUDE.md §1 の接続

- §1 に thinking.md への参照を記載（MUST ライン）
- テンプレート版: 2-3行の参照のみ
- Private sidekick: 脳tion のエッセンスを注入（PJ固有の判断軸として）

### 3. 成長サイクルの認知

- セットアップ時に強制しない
- session-start.sh で棚卸し期限チェック（7日超で WARNING）
- weekly-inventory に思考OS健康度チェック（Step 0）を追加
- ライフサイクルの説明は README に記載

### 4. README の再構成

- 差別化の軸を「安全」→「思考OS + 知識の複利」に変更
- thinking.md の入れ替え可能性を前面に
- 成長サイクル（feedback → 原則 → 思考OS）を可視化

## トレードオフ

- セットアップ時に強制しないため、thinking.md が育つまで時間がかかる
- hooks が入っていない導入パターンでは、棚卸しリマインドが機能しない
- README での訴求に依存する部分が大きい

## 補足

- 脳tion（Notion AI 思考OS）と sidekick の thinking.md は同じ思想から生まれている
- 脳tion = 手動で育てる思考OS、sidekick = 自動で育つ思考OS（feedback → 昇格が仕組み化）
- 将来的に thinking-os-template（スタンドアロン版）を別リポで提供し、sidekick へのファネルとする構想あり
