---
name: system-map
description: Next.js（App Router + Prisma）コードベースを「画面 ↔ API ↔ DB ↔ 権限 ↔ 遷移」の単一 HTML 地図に可視化する。硬い層（静的解析）で大半を決定的に抽出し、軟らかい層（ドメイン別サブエージェント）で意図を補う。影響調査・オンボーディング・設計レビューに使う。
allowed-tools: Read, Grep, Glob, Bash, Write, Agent
---

# /system-map — Next.js システム地図

コードベースを 1 枚の単一 HTML（依存ゼロ・オフライン動作）に可視化する。**規定アーキ（`ARCHITECTURE.md` の golden path）に従う PJ ほど、地図は決定的に・自動的に描かれる**。

> 前提: この skill は **Next.js stack pack** の一部。可視化の対象 PJ は `ARCHITECTURE.md` の golden path（DAL・Server Action・命名ブリッジ等）に概ね従っていることを想定する。従っていない箇所は軟層が推測で埋める（地図に `uncertainties` として残す）。

## 出力パイプライン

`data/*.json`（硬層 + 軟層が生成）→ `assets/merge.js` → `combined.json` → `assets/build.js` → `system-map.html` → `assets/verify.js`（自己検証）。

データ契約は `schema.md`、硬/軟層の配分は `methodology.md` を参照。

## 手順

### Step 0: 対象の確認
- 対象 PJ のルート（`grep "^DATABASE_URL" .env` は不要 — DB 接続はしない。**静的解析のみ**）。
- `prisma/schema.prisma`・`app/` ディレクトリ・`middleware.ts` の有無を確認。無ければユーザーに対象パスを聞く。
- 作業ディレクトリを決める（例: `<対象PJ>/docs/visualization/`）。`data/` を作る。

### Step 1: 硬い層（決定的・無 LLM）— adapter で骨格を全自動生成
`assets/adapters/` の adapter を順に実行し `data/` に**骨格**を出す。**LLM ゼロ・冪等**。golden path 準拠 PJ ほど欠損なく出る。

```bash
PACK=<pack>/skills/system-map/assets
node $PACK/adapters/extract-schema.nextjs.js  <対象> data/db-schema.json          # 列・型・PK/FK・relations・accessedFrom(1:N)
node $PACK/adapters/extract-indexes.nextjs.js <対象>/prisma/schema.prisma data/db-indexes.json
node $PACK/adapters/extract-routes.nextjs.js  <対象> data                          # <domain>.json を複数生成: screen+api（kind★S4/trigger/validation/dbTablesRead-Write/calledByScreens）
node $PACK/adapters/extract-authz.nextjs.js   <対象> data/permissions.json          # roles(enum)/requireSession・requireRole/out-of-band realm(署名・cron secret)/spaGuards
node $PACK/adapters/extract-links.nextjs.js   <対象> data/flow-structure.json       # Link/router.push/redirect → 遷移 edges
```

> 出力は **骨格**（identity・`api.kind`★S4・`trigger`・`validation` 分類・`dbTables`・認可ゲート・遷移）。`purpose`/`summary`/`gotchas`/画面 `kind` の意味/`idempotency` 判定/object-level 認可は空 or `uncertainties` で残る → Step 3 軟層が enrich する。
> **この時点で Step 4 を回せば「骨格だけの地図」が既に描ける**（軟層は任意・複利の本体は硬層）。正準カウント（route/screen/action/mutation）は `route-enumerator.js` が単一定義で adapter が import する（fitness と母集合一致）。SOFT 残差・1ホップ制限等は `assets/adapters/README.md`。

### Step 2: ドメイン分割
- **`extract-routes` が決定的に分割済み**（route group `(x)` or `api`/動的 segment を除いた先頭 segment = domain）。生成された `data/<domain>.json` のファイル名がドメイン一覧。
- 分割が意味的に不適切な箇所だけ軟層で見直す（例: 横断モデルの主ドメイン）。

### Step 3: 軟らかい層（ドメイン別サブエージェント＝ファンアウト）— 骨格を enrich
- **ドメイン 1 つ = `Agent` 1 つ**で並行起動（`methodology.md` のファンアウト戦略）。**ゼロから作らず、Step 1 が出した `<domain>.json` の骨格を上書き enrich** する。
- 各エージェントに渡す: 担当ドメインの `data/<domain>.json`（骨格）+ 該当ルート群 + `schema.md`。
- 各エージェントの **Return Contract**: enrich 済み `<domain>.json`（`schema.md` の形）だけを返す。骨格の identity/kind/trigger は壊さず、`purpose`/`summary`/画面 `kind` の意味/`gotchas`/`uncertainties` の解消を埋める。生レスポンス・全文は返さない。
- 画面遷移の意味（contextual な遷移ラベル等）は `flow-structure.json`（or `flow-<domain>.json`）を enrich。

### Step 4: マージ & ビルド & 検証
```bash
cd <pack>/skills/system-map/assets
node merge.js <対象>/docs/visualization/data <対象>/docs/visualization/combined.json
node build.js template.html <対象>/docs/visualization/combined.json <対象>/docs/visualization/system-map.html
node verify.js <対象>/docs/visualization/system-map.html   # → PASS を確認
```
`verify.js` が FAIL なら、該当ルートの JSON を直して再ビルド（Gotchas 参照）。

### Step 4.5: 鮮度マーカーを記録（`/review` の drift 検知用）
生成した地図が「どの構造に対して作られたか」を正準カウントで刻む。次回以降 `/review` の fast-gate が
この marker と現在のコードを比較し、構造が変わっていれば「🗺 地図が古い」と 1 行 nudge する（生成は強制しない・ADR-0022 C+A）。

```bash
node <pack>/fitness-functions/canonical-counts.js <対象> > <対象>/.claude/.system-map-counts.json
```

> **per-dev の鮮度マーカー**: このファイルは「自分が最後に地図を生成した時点の構造」を表す。`.gitignore` に
> `.claude/.system-map-counts.json` を追加推奨（コミットしない＝再生成毎のコミットノイズを避ける・軽さ優先）。
> チームで「地図の古さ」を共有したい場合のみコミット運用に切り替える。

### Step 5: 確認・引き渡し
- `system-map.html` をブラウザで開いて確認（単一ファイル、共有可能）。
- `uncertainties` が多い箇所は golden path 非準拠の疑い → ユーザーに報告。

## Return Contract（この skill 全体）

### 返すもの
- 生成した `system-map.html` のパスと、ドメイン数・画面数・API 数・モデル数・`verify.js` の結果。
- golden path 非準拠で軟層推測に落ちた箇所（`uncertainties`）のサマリ。

### 返さないもの
- 中間 JSON の全文・`template.html` の中身・各サブエージェントの生レスポンス。

## Gotchas
- **`verify.js` の boot fail** = 埋め込み JSON か app JS の構文崩れ。`combined.json` を JSON として開いて検査。
- **ルートが地図に出ない** = `<domain>.json` の `screens[].route` / `apis[].path` 欠落。硬層の素材と突き合わせる。
- **FK が ER に出ない** = `db-indexes.json` 未生成 or `schema.prisma` の `@relation(fields/references)` 欠落。Step 1.1 を再実行。
- **`api.kind` バッジが出ない** = `<domain>.json` の `apis[].kind` 未設定。Server Action か Route Handler かを Step 1.4 の判定で埋める。
- **生成物はコミットしない**: `combined.json` / `system-map.html` / `db-indexes.json` は再生成可能な成果物。対象 PJ 側で `.gitignore` するか、地図 HTML だけ共有する。
- **静的解析のみ**: DB 接続・コード実行はしない。`schema.prisma` とソースの読み取りだけ。
