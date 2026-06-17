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

### Step 1: 硬い層（決定的・無 LLM）
順に実行し `data/` に出す。

1. **DB 索引**: `node <pack>/skills/system-map/assets/adapters/extract-indexes.nextjs.js <対象>/prisma/schema.prisma data/db-indexes.json`
2. **モデル**: `schema.prisma` から `db-schema.json`（モデル名・列・型・PK/FK）。列挙は決定的、`purpose` の意味付けは Step 3 で軟層が足す。
3. **ルート一覧**: `app/**/page.tsx` と `app/api/**/route.ts` を Glob → 画面・API の素材。
4. **mutation 面**: `"use server"` を含むファイルの export 関数 = Server Action、`route.ts` の export = Route Handler（`api.kind` ★S4）。
5. **認可**: `middleware.ts` の matcher と DAL の `requireRole`/所有検証を grep → `permissions.json` の素材。

> 硬層の素材は LLM に丸読みさせない。Step 3 のサブエージェントには「担当ドメイン分の素材」だけ渡す（トークン節約）。

### Step 2: ドメイン分割
- ルート・モデルをドメイン（機能のまとまり）に割る。`app/(group)/` のルートグループや DAL のモジュール境界が手がかり。
- ドメインのリストを決める（例: `content`, `account`）。

### Step 3: 軟らかい層（ドメイン別サブエージェント＝ファンアウト）
- **ドメイン 1 つ = `Agent` 1 つ**で並行起動（`methodology.md` のファンアウト戦略）。
- 各エージェントに渡す: 担当ドメインのルート群 + Step 1 の素材 + `schema.md`。
- 各エージェントの **Return Contract**: `<domain>.json`（`schema.md` の形）だけを返す。画面の意図・API の効果・`gotchas`・`uncertainties` を埋める。生レスポンス・全文は返さない。
- 画面遷移は `flow-<domain>.json`（`screens[]` + `edges[]`）に出す。

### Step 4: マージ & ビルド & 検証
```bash
cd <pack>/skills/system-map/assets
node merge.js <対象>/docs/visualization/data <対象>/docs/visualization/combined.json
node build.js template.html <対象>/docs/visualization/combined.json <対象>/docs/visualization/system-map.html
node verify.js <対象>/docs/visualization/system-map.html   # → PASS を確認
```
`verify.js` が FAIL なら、該当ルートの JSON を直して再ビルド（Gotchas 参照）。

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
