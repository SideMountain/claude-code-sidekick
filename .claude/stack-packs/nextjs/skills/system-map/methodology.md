# system-map 方法論（Next.js）

「コードベース → 単一 HTML 地図」を**できるだけ硬い層（決定的・無 LLM）**で生成し、軟らかい層（LLM）はドメインの意味付けに限定する。これが「地図が自分で描かれる」（北極星）の実体。

## 硬い層 / 軟らかい層の配分

| 抽出物 | 層 | Next.js での当て方 |
|---|---|---|
| ルート一覧 | **硬** | `app/**/page.tsx` / `route.ts` のファイル走査 |
| Prisma モデル・列・PK/FK/UNIQUE/INDEX | **硬** | `adapters/extract-indexes.nextjs.js`（`schema.prisma` を regex 抽出） |
| API→DB の読み書き対象 | **硬寄り** | DAL（`lib/dal/**`）の Prisma 呼び出しを辿る（S2 が効くほど決定的） |
| mutation 面（Server Action / Route Handler） | **硬** | `"use server"` pragma・`app/api/**/route.ts` の export を判定（S4） |
| 認可グループ・middleware matcher | **硬寄り** | `middleware.ts` の matcher と DAL の `requireRole` を読む（S5） |
| 画面遷移（`<Link>` / `useRouter().push`） | **硬寄り** | grep で双方向リンクを構築 |
| ドメインの目的・画面の意図・gotchas | **軟** | ドメイン単位のサブエージェント（LLM） |

> **規約が効くほど硬くなる**: `ARCHITECTURE.md` の golden path に従う PJ ほど、上表の「硬寄り」が「硬」に寄る。決定性の最終的な範囲は `ARCHITECTURE.md` の決定性スコープ表を参照。SOFT 残差（対話的 leaf の fetch・動的クエリの model 到達・行レベル業務認可・帯域外 auth）は軟層が埋める。

### 硬層 adapter の原則（dogfood で確立）

- **コメントを一次ソースにしない**: 抽出の一次ソースは**式・export・import グラフ・設定ファイル**。コメントは実装と矛盾しうる（dogfood で `middleware.ts` のコメントが matcher 式と矛盾＝「api を除外」と書くが実際は除外せず、の実例）。地図はコードの実体を写す。
- **enumerator の正準カウントを凍結**: route 数は数え方で揺れる（ファイル数 / method export 数 / page+API 合算）。adapter は **route enumerator を単一定義に固定**し（推奨: route.ts × 各 method export = 1 entry / page.tsx = 1 screen）、全出力がそれを参照する。母集合が未確定のまま HARD/SOFT を語らない。
- **mutation は trigger 別に列挙**: page 到達分だけでなく cron（`vercel.json` crons 等）・webhook も列挙対象（`ARCHITECTURE.md` S4。page から辿れない高 blast-radius 入口を取りこぼさない）。
- **`none` を即「欠落」と断じない**: validation `none` でも `auth-gate`/`signature`/`file` は正当な入力境界。検証 taxonomy で分類してから比率を出す。

## ファンアウト戦略（軟層）

ドメインを跨いだ巨大プロンプトにしない。**ドメイン 1 つ = サブエージェント 1 つ**で並行生成し、各エージェントは `<domain>.json` だけを返す（Return Contract）。

1. 硬層パーサで「ルート / API / モデル / 認可」の素材を先に出す（決定的・全ドメイン共通）
2. ドメインごとにサブエージェントを起動。各エージェントには「担当ドメインのルート群 + 素材」だけ渡す
3. 各エージェントは `<domain>.json`（画面の意図・API の効果・gotchas・uncertainties）を返す
4. `merge.js` で統合 → `build.js` → `verify.js`

これでメインコンテキストを汚さず、トークンもドメイン分割で節約できる。

## トークン節約

- 硬層の出力（ルート・モデル・索引）はコードから決定的に出るので **LLM に読ませない**。サブエージェントには「結論の素材」だけ渡す。
- `verify.js` は LLM 不要の自己検証（DOM スタブで全ルート描画）。生成のたびに回す。
- 大きい `template.html` はメインで読まない。`build.js` が機械的に差し込む。

## 維持（drift gate）

地図は一度作って終わりではない。`ARCHITECTURE.md` の golden path に従う限り、**硬層は再生成するだけで最新化される**。

- 硬層（`extract-indexes.nextjs.js` + ルート走査）を CI / pre-PR で再実行し、`combined.json` の diff を見る
- 構造が変わった（新ルート・新モデル・新 mutation）のに地図が古ければ drift。再生成を促す
- 将来 `fitness-functions/`（検知層）が「規約違反」と「地図 drift」を同じ仕組みで落とす（pack roadmap 参照）

## サンプル

`assets/sample-data/`（generic blog/CMS）が最小の実例。パイプライン:

```bash
cd assets
node adapters/extract-indexes.nextjs.js sample-data/schema.prisma sample-data/data/db-indexes.json
node merge.js sample-data/data sample-data/combined.json
node build.js template.html sample-data/combined.json sample-data/system-map.html
node verify.js sample-data/system-map.html   # → PASS（全ルート描画）
```
