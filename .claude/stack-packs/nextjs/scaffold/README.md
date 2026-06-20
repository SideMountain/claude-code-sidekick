# scaffold — golden path skeleton 生成器

新規 PJ（または既存 PJ への 1 feature 追加）を**最初から `ARCHITECTURE.md` の規約に乗せる**ための skeleton。
「認知 → **強制（ここ）** → 検知（fitness）」の強制層 — 違反コードを書く前に、正しい型で土台を置く。

## 使い方

```bash
node .claude/stack-packs/nextjs/scaffold/scaffold.js <targetDir> [--force]
```

`template/`（規約を満たす具体 vertical slice・feature=`posts`）をコピーする。
出力後の手順は scaffold 実行時のメッセージに従う（install → migrate → feature 複製 → `test:arch`）。

### 空ディレクトリ vs create-next-app へのオーバーレイ

pack は Next アプリ本体を作らない。通常は先に `create-next-app` で土台を用意し、その上に重ねる:

- **既存ディレクトリ（create-next-app 済み）**: `--force` が必須（非空ガード）。`package.json` は
  **破壊的に上書きせず非破壊マージ**する — 既存の `name` / `version` / 解決済み依存バージョンを保持し、
  golden path の script（`test:arch` 等）と不足依存（`@prisma/client`・`zod`・`server-only`・`prisma`）だけ足す。
  その他 config（`tsconfig`/`next.config`/`eslint`/`.gitignore`/`layout`）は golden path 版で上書きする（同形・意図的）。
- **create-next-app の既定ファイルの後始末**: `app/page.tsx` / `app/globals.css` は golden path 外（layout は
  CSS を import しない）。残すと fitness の screen 数 / system-map に余分な画面 `/` として出るため、scaffold が
  検知して削除を促す。削除するか `app/page.tsx` を `/posts` へのリダイレクトに置換する。
- **空ディレクトリ**: そのまま template を展開（`--force` 不要・`package.json` はテンプレ版）。

## 何を置くか（`posts` 縦スライス = 手本）

| ファイル | 体現する規約 |
|---|---|
| `tsconfig.json`（`@/*` paths） | S1 |
| `lib/prisma.ts`（singleton + soft-delete `$extends`） | H1 |
| `lib/auth/session.ts`（単一 helper・enum role・discriminated union） | S5 |
| `lib/validations/post.ts`（Zod named schema + `z.infer`） | S7 |
| `lib/posts/{queries,mutations}.ts`（DAL・`server-only`・object-level スコープ・命名ブリッジ） | S2 / S6 / S8 / H4 |
| `app/posts/page.tsx`（server-first・props 渡し） + `error.tsx` / `loading.tsx` | S3 / H3 |
| `app/posts/actions.ts`（module-level `'use server'`） | S4 |
| `app/api/posts/route.ts`（gate→validate→service→respond・prisma 非 import） | S2 / S7 |
| `app/api/webhooks/billing/route.ts` + `lib/billing/webhook.ts`（webhook trigger・冪等性） | S4 / H2 |
| `app/api/cron/digest/route.ts` + `lib/digest/send.ts`（cron trigger） | S4 |

`posts` slice は**複製して新 feature を作る手本**。各層の規約はファイル先頭コメントに明記してある。

## fitness との関係（co-validation）

`template/` は **fitness-functions の conforming fixture と同一ファイル**。つまり:

- scaffold が生む土台は**定義上 fitness green**（`run-fitness.js` で error 0 / warn 0 を確認済み）
- 逆に fitness は scaffold 出力という「conforming な実例」で false-positive がないことを保証される

契約（fitness）と生成器（scaffold）が互いの受け入れテストになり、ドリフトしない。

## 注意

- `gitignore`（dot なし）を出力時に `.gitignore` へリネームする（pack 内では tracked テンプレとして dot なし保管）。
- **feature 名のパラメタ置換（`posts`→任意）は未実装**: camelCase 複合識別子（`createPostAction` 等）の安全置換が要るため。現状は verbatim コピー + 手動複製。将来拡張。
- scaffold は **pack を取り込んだ PJ（`STACK_PACK: nextjs`）** 前提（`test:arch` が pack のパスを参照する）。
