# anti-slop 憲章（UI/UX + 文書）— ADR-0019 P1 合流素材

> UI と文書の「AIっぽさ」（slop = モデルが安全・無難な既定値に滑り込むことで生じる様式化）への対抗設計。
> **本ドキュメントは起草（実装素材）**。実装・配布は ADR-0019 P1（design-system.md + PostToolUse 検知 hook +
> `/setup` UI opt-in + review 接続）に合流する。検知パターンは fixture の正例・負例に加え、
> 敵対検証（独立 1 本・リポ実文書への実走を含む）を通して確定した（§4 検証記録）。

## 0. 設計原則（2 本柱）

slop は「禁止リスト」だけでは消えない — 無難の回避は無難の変種を生むだけで、個性は生まれない。

| 柱 | 何をするか | 3 層での位置 |
|---|---|---|
| **柱 1: 負の閉集合** | 既定値への滑り込みを決定的に検知（機械検査・advisory WARN） | 検知 |
| **柱 2: 正の個性** | PJ 固有の taste を **自リポの最良実例（exemplar anchor）** から注入 | 認知 |

既存レイヤーとの関係（重ねる、作らない）:

- 書きぶりの認知層は `rules/oss-doc-authoring.md`（SOFT）が既に持つ。柱 1 の文書系はその**決定的サブセット**（検知層）
- UI の生成層は外部スキル（生成 = frontend-design / 磨き = baseline-ui 系）を `/setup` が**推奨案内**する。ccs は生成を再発明せず強制・検知に専念する（ADR-0019）
- 負の閉集合は **R6 致命クラスと同じ閉集合規律**: メンバーの追加・変更には正例・負例の実走検証を要求し、際限なく増やさない

**パターンの単一ソース**: 検知 regex の正は実装時の `.claude/scripts/detect-slop.sh`（`detect-hard-spot.sh` と同型・advisory・常に exit 0）に置く。本憲章はメンバーシップ（何を slop とみなすか）と誤検知への配慮だけを規定し、regex を二重管理しない。

## 1. 柱 1: 負の閉集合（決定的検知）

全て **WARN（advisory）**。deny しない — taste は物理ブロックの対象ではない（ブラックリスト方式の「禁止」はデータ・安全のみ）。opt-out の仕様は §2.3。

### スコープの決定（発火条件を設定ファイルに従属させる）

| 系 | 発火条件 | 不在時 |
|---|---|---|
| U 系（UI） | `design-system.md` が存在する PJ の UI 拡張子（`*.tsx *.jsx *.vue *.svelte *.css *.scss *.html`）。`tokens_files:`・`assets_dirs:` に列挙されたトークン定義・配布アセットは除外 | **発火しない**（token が無い PJ に token 準拠は要求できない。UI なし PJ 無コストの ADR-0019 原則） |
| W 系（文書） | `writing-charter.md` の `scope_files:` に列挙された glob（例: `README* docs/*.md`）のみ | **発火しない**（U 系と同型）。内部設計ドラフト（`.claude/docs/` 等）を scope に含めない運用を既定とし、検知パターンのリテラルを含む文書の自己発火を構造的に回避する |

> **ADR 整合の明示**: 文書系（W）は ADR-0019 の決定範囲（UI/UX・UI あり PJ のみ）の**外**にある。実装時は
> **姉妹 ADR（文書 anti-slop・writing-charter opt-in）を起こす**ことを推奨する — ADR-0019 の「UI なし PJ 無コスト」
> 原則を UI の文脈に保ったまま、文書系を独立の opt-in として扱える（ADR-0019 自体の改訂は不要になる）。

### U 系（UI）

| ID | slop | 検知の仕様 | 誤検知・見逃しへの配慮 |
|---|---|---|---|
| **U1** | 紫グラデ既定(AI UI の代表的様式) | **ファイル単位の 2 条件 AND**: 同一ファイル内に (a) `(linear\|radial\|conic)-gradient` or `bg-gradient-` と (b) 紫既定色 — Tailwind 数値スケール形 `(from\|via\|to)-(purple\|violet\|fuchsia\|indigo)-[0-9]` or 既定 hex 閉集合（`#667eea #764ba2 #8b5cf6 #a855f7 #7c3aed #6366f1 #9333ea #d946ef #c026d3`・**大文字小文字不問**）— の両方が存在したら、両方の行番号付きで WARN | 行単位 AND では prettier 整形の複数行 CSS・clsx/cn で分割された JSX（React の最頻出形）を見逃すため**ファイル単位**にする。`var(--brand-purple)` 等トークン経由の意図的パープルは非検知（検証済み）。ファイル単位化による誤検知（gradient と紫が無関係に同居）は advisory WARN の許容範囲とし、行番号提示で人が 3 秒で棄却できる形にする |
| **U2** | 非トークン hex 直書き | `#[0-9a-fA-F]{3,8}` の word-boundary 付き検知（3/4/6/8 桁 = alpha 付き含む） | `tokens_files:`（tailwind.config 等）と `assets_dirs:`（自己完結型の配布 HTML 等、トークン定義と使用が同居する単一ファイルを含むディレクトリ）は除外。design-system 不在 PJ では不発火 |

### W 系（文書）

| ID | slop | 検知の仕様 | 誤検知・見逃しへの配慮 |
|---|---|---|---|
| **W1** | 絵文字見出しの乱用 | 行頭見出し（`^#{1,6}\s`）直後の絵文字を数え **≥ 3 / ファイルで WARN**。絵文字 range は `\x{1F000}-\x{1FAFF} \x{2600}-\x{27BF} \x{2B00}-\x{2BFF}`（Unicode ブロックを明記 = 第三者が再現可能） | 1–2 個は個性の範囲。⚠️（U+26A0）は range に**含まれる**が、ccs の温度感マーカーは表・blockquote 内で行頭見出しに現れないため非該当（実走確認済み）。ccs 自身の `README*`（絵文字見出し 6 件）は**真陽性** — 配布前に修正 or 理由付き opt-out を裁定する（§4） |
| **W2** | 装飾絵文字の焚き付け | 閉集合 `🚀 ✨ 🎉 🔥 💪 🌟 💯 🎊` の出現 **≥ 5 / ファイルで WARN**。**選定基準 = 「情報を運ばない祝祭・煽り系」**（status・温度感を運ぶ ✅ ❌ ➖ ⚠️ 💡 は対象外）。境界例（⚡ 🎯 ⭐ 等）の追加は R6 型 — 実文書での slop 正例 3 件を示してから | 情報絵文字を含めないことで ccs の診断文書・CHANGELOG の status 表では誤検知ゼロ（実走確認済み） |
| **W3** | 議論経緯の時系列描写 | `壁打ちで\|再検討の結果\|当初の判断を覆` | oss-doc-authoring「書かない」の決定的サブセット。リポ実走で既存 ADR 1 件の真陽性を検出済み（検知層として機能する証左）。「以前は」は CHANGELOG の正当な before 記述と衝突するため見送り |

### 閉集合に入れなかったもの（silent drop 禁止 — 理由付き見送り）

| 候補 | 見送り理由 |
|---|---|
| 任意 px 値（magic spacing） | 正当な `1px` border 等で誤検知率が高い。P2 デザイントークン lint の守備範囲 |
| Inter/Roboto 既定フォント | font 指定の書式が多様で grep が構造依存。生成層（frontend-design）が既に矯正する |
| AI 常套句（「いかがでしたか」等） | ブログ体裁の PJ でのみ意味を持ち、汎用の閾値が切れない。writing charter の exemplar（正の側）で矯正 |
| 「以前は」（時系列マーカー） | CHANGELOG の正当な before 記述と衝突（負例検証で確認） |

## 2. 柱 2: 正の個性（exemplar anchor）

固定のサンプル UI・サンプル文体を**配布しない**。配布サンプルは全下流で同じ「正解」を複製し、それ自体が新しい様式化（slop）になる。代わりに **exemplar anchor** — 実行環境の自リポにある最良実例への参照 — を使う。`/record-decision` の ADR exemplar 方式と同型だが、その類推が成立するのは**人間が指名した具体アンカーがある場合**に限る（下記 bootstrap 規律）。

### 2.1 テンプレ骨子（P1 で `.claude/templates/` に追加・`/setup` が配置）

```markdown
# design-system.md（PJ が育てる・配布時はプレースホルダ。paths: frontmatter で UI 拡張子に
# path-scoped 化する — 既存ファイル編集時の補助。主機構は PostToolUse hook〔ADR-0019〕）
## Voice          — この PJ の UI が与えるべき印象 / 避ける印象（各 1-2 行）
## Tokens         — 色・spacing・type scale の定義 or 定義ファイルへのポインタ
tokens_files:     — トークン定義ファイルの列挙（U2 除外リストの単一ソース）
assets_dirs:      — 自己完結型配布アセットのディレクトリ（U2 除外）
## Exemplar       — 自リポの最良 UI 実例 1-2 ファイル。「新規 UI はまずこれを Read してから書く」
## opt-out        — §2.3 の仕様に従う（ID + スコープ + 理由）
```

```markdown
# writing-charter.md（文書を持つ PJ 向け・姉妹 ADR の opt-in）
scope_files:      — W 系の検査対象 glob（README* docs/*.md 等）。W 系発火の単一ソース
## 読者と媒体      — 読ませる文書(図解)/ 引かせる文書（表）の別と代表読者
## トーン         — 結論ファースト等。結論・教訓を明示する文書か、余白に置く文書か
## Exemplar       — 自リポの最良文書 1-2 本
## opt-out        — §2.3 の仕様に従う
```

### 2.2 bootstrap 規律（exemplar の自己強化ループを断つ）

自リポ参照には自己強化リスクがある: 新規 PJ の初代 UI はモデル既定（= slop 傾向）で書かれ、それが exemplar に座ると以後の全 UI が slop を複製する。対策を機構に組み込む:

- **Exemplar 空欄時は anchor 手順を skip する**（柱 1 のみ有効）。空欄のまま動くことを明示し、「とりあえず何か指す」を許さない
- **初代 exemplar は人間の明示的指名を必須**とする（`/setup` / セッション中の「これを exemplar にして」）。エージェントが自動指名しない — record-decision 類推の成立条件（人間キュレーションされたアンカー）を UI/文書側でも守る
- 指名候補は**指名前に U 系検知を通す**（slop 検知に引っかかる実例を anchor に座らせない）
- 再指名トリガ: PJ オーナーが更新を宣言した時 + `/weekly-inventory` が「exemplar 空欄 or 6 ヶ月未更新」を報告した時

### 2.3 opt-out 仕様（全無効化への滑りを構造で防ぐ）

| 規律 | 内容 |
|---|---|
| スコープ付き | `- U1: paths: ["src/components/Brand*"] reason: ブランド色が紫` の形式。**PJ 全域の opt-out は reason に「全域である理由」を要求**（1 コンポーネントの例外で PJ 全体の検知を殺さない） |
| 自己消音の顕在化 | design-system.md / writing-charter.md の **opt-out 節に触れる diff は決定的検査が必ず WARN** し `/review` の入力にする（WARN を受けた同一セッションのエージェントが opt-out を書き足して静音化する経路を可視化する） |
| 全体状態の報告 | 決定的検査は実行時に「現在 opt-out 中の ID 一覧」を毎回出力する（全 ID opt-out = 事実上の無効化が silent にならない） |

## 3. ADR-0019 P1 実装への写像

| 部品 | 本憲章からの入力 | 層 |
|---|---|---|
| `.claude/scripts/detect-slop.sh` | U/W 全パターンの単一ソース（detect-hard-spot.sh と同型・advisory・exit 0 固定）。opt-out 状態の報告を含む | 検知 |
| PostToolUse UI 検知 hook | Write/Edit 対象が UI 拡張子 + design-system.md 存在時に detect-slop.sh の U 系を呼び `additionalContext` で WARN（deny しない・lint は実行しない = PR 前ゲート一本化の決定を維持） | 検知 |
| 決定的検査（fitness 前置） | PR 前に W 系 + opt-out 節 diff 検査を実行し `/review` へ WARN 入力 | 検知 |
| REVIEW.md §1e 拡張 | design-system.md / writing-charter.md の双方を参照し、U/W 系は**機械検知の結果を参照**（機械で分かることは LLM に判定させない） | 認知 |
| `/setup` opt-in | UI あり申告 → design-system.md 配置 + hook 配線 + 外部スキル（生成/磨き層）の推奨案内 + 初代 exemplar の人間指名ヒアリング。文書 charter は公開 docs を持つ PJ に提案（姉妹 ADR） | 認知 |
| `/verify` 委譲ポインタ | UI 変更の動作実証は公式 `/verify`（実画面・実フロー）に委譲し、本ハーネスは静的検知に閉じる（ADR-0019 P1 の 4 項目目） | 検知 |

配布前に UI を持つ下流 PJ で 1 サイクル dogfood する（ADR-0019 影響欄）。W 系は ccs 自身が dogfood 対象（`README*` の W1 真陽性の裁定を含む — §4）。

## 4. 検証記録と既知の限界

**検証の経路**（fixture → 敵対検証 → 反映）:

1. fixture 正例・負例: U1 = 4/0（トークン経由パープル非検知を含む）/ W1 = 4/0 / U2 = 2/0 / W2 = 6/0（status 表・温度感マーカーで誤検知ゼロ）/ W3 = 3/0
2. 敵対検証（独立 1 本・リポ実文書への実走を含む）が以下を特定し、本版に反映済み:
   - U1 の行単位 AND は複数行 CSS・clsx 分割 JSX・大文字 hex を見逃す → **ファイル単位 AND + 大文字不問 + fuchsia hex 追加 + radial/conic 追加**
   - U2 の 6 桁限定は `#fff` / alpha 付き 8 桁を見逃す → **3–8 桁化**。配布アセット（トークン定義同居の自己完結 HTML）が大量ヒット → **`assets_dirs:` 除外を新設**
   - 検知パターンのリテラルを含む文書（本憲章等）が W 系に自己発火 → **`scope_files:` 従属化で構造解決**
   - ccs の `README*` が W1 に該当（絵文字見出し 6 件・真陽性）→ **実装時の裁定事項として起票**（修正 or 理由付き opt-out。dogfood の第 1 号）
   - W3 がリポ内の既存 ADR 1 件で真陽性を検出（検知層として機能）
3. 実装時は detect-slop.sh に fixture（正例・負例）を同梱し、パターン変更のたびに再走できる形にする（guard-oracle と同じ「実走が期待値」の規律）

**既知の限界**（受容 + 明記）:

- 絵文字 range 検知は `grep -P`（GNU grep）前提。`-P` 非対応環境では W1/W2 を skip し、skip した事実を WARN で出す（silent drop しない）
- U1 のファイル単位 AND は「gradient と紫が無関係に同居する大きなファイル」で誤検知しうる（advisory WARN + 行番号提示で許容）
- 閾値（W1 ≥3 / W2 ≥5）は初期値。dogfood の誤検知・見逃しを ledger に記録して較正する

## 5. スコープ外

デザイントークン lint（warn→error）・a11y smoke（axe）= P2、ビジュアルリグレッション = P3（ADR-0019 のまま変更なし）。文書系（W）の正式な意思決定は実装時の姉妹 ADR で行う（§1 スコープの決定）。
