# system-map データ契約（Next.js）

system-map は「入力 JSON 群（`data/*.json`）→ `merge.js` → `combined.json` → `build.js` → 単一 HTML」というパイプライン。本書は各 JSON の形を定義する。**この契約はスタック非依存のメタモデル**（画面・API・DB・権限・遷移）であり、Next.js 固有の項目だけを `[Next]` で示す。

> アーキテクチャ規約そのものは pack 直下の `ARCHITECTURE.md`（golden path）を正とする。本書はそれを *可視化するための* データ形式。

## 入力ファイル（`data/` に置く）

`merge.js` はファイル名と中身の形で種類を自動判別する。

| ファイル | 形の判別 | 生成方法 |
|---|---|---|
| `permissions.json` | ファイル名固定 | 軟層（ロール・認可の読み取り） |
| `db-schema.json` | ファイル名固定 | 軟層（モデルの意味付け）+ 硬層（列・型・PK/FK） |
| `db-indexes.json` | ファイル名固定 | **硬層**: `adapters/extract-indexes.nextjs.js` が `schema.prisma` から生成 |
| `<domain>.json` | `id` を持つ | 軟層（ドメインのサブエージェント） |
| `flow-<x>.json` | `screens[]` と `edges[]` を持ち `domains`/`apis` を持たない | 軟層（画面遷移） |

## `<domain>.json`

```jsonc
{
  "id": "content",                 // 一意キー（kebab）
  "name": "コンテンツ",             // 表示名
  "purpose": "…",                  // ドメインの目的（1-2文）
  "screens": [{
    "id": "post_editor",
    "title": "記事エディタ",
    "route": "/dashboard/posts/[id]",  // [Next] App Router のルート（[id] 等の動的 segment 可）
    "module": "my-page",               // public | my-page | manage | auth（任意の分類キー）
    "kind": "form",                    // 画面種別: list|form|detail|confirm|complete|login|menu|top|... 
    "permission": "authenticated",
    "userTypes": ["author", "admin"],
    "actions": [{"label": "保存", "api": "POST savePost"}]  // api は <method> <path|operationId>
  }],
  "apis": [{
    "method": "POST",
    "path": "savePost",                // route handler は "/api/…"、Server Action は関数名
    "operationId": "savePost",
    "kind": "server-action",           // [Next] route-handler | server-action | webhook | cron ★S4
    "trigger": "page",                 // [Next] page | scheduler | provider-callback | internal（mutation の発火元）
    "summary": "…",
    "permission": "authenticated",
    "dbTablesRead": ["Post"],          // Prisma モデル名
    "dbTablesWrite": ["Post"],
    "calledByScreens": ["post_editor"],
    "validation": "body-schema",       // [Next] body-schema | file | auth-gate | signature | none
    "idempotency": "n/a",              // [Next] webhook/cron 用: event-id-dedup | provably-idempotent | unguarded | n/a
    "gotchas": ["…"]                   // 任意
  }],
  "gotchas": ["…"],                    // ドメイン横断の罠（overview に集約表示される）
  "uncertainties": ["…"]               // 未確定・要確認
}
```

`kind`（API）は Next.js の **mutation 面**を表す中心項目（`ARCHITECTURE.md` S4）。

- `server-action` = 内部 mutation（module-level `actions.ts`・inline closure 禁止）/ `route-handler` = 外部向け（`app/api/**/route.ts`）/ `webhook` = provider-callback / `cron` = scheduler。HTML 上でバッジ表示される。
- **`trigger`**: mutation の発火元。`page`（screen から到達）以外に `scheduler`(cron) / `provider-callback`(webhook) / `internal` がある。**②③ は page から辿れないが blast-radius が大きい**ため必ず列挙する（S4）。
- **`validation`**: `none` を即「検証なし」と断じない。`auth-gate`（cron secret 等）・`signature`（webhook 署名）・`file`（multipart）は body-schema 以外の正当な入力境界（dogfood の「47% 無検証」はこれらの誤算入を含む）。
- **`idempotency`**: `webhook`/`cron` は at-least-once 前提。`unguarded`（event-id dedup も冪等保証も無し）を flag する（`ARCHITECTURE.md` H2）。

## `permissions.json`

```jsonc
{
  "roles": [{"code": "admin", "name": "管理者", "scope": "manage", "description": "…"}],
  "endpointAuth": [{                   // 認可グループ（[Next] middleware matcher / route handler auth）
    "authGroup": "admin", "paths": ["/admin", "/api/admin"],
    "permitAll": false, "source": "DAL requireRole('admin')"
  }],
  "spaGuards": [{                      // ルート/ミドルウェアガード
    "module": "manage", "routePath": "/admin",
    "requiredPermission": "admin", "userTypes": ["admin"]
  }],
  "notes": ["…"], "uncertainties": ["…"]
}
```

> [Next] 認可は二層。`endpointAuth` は middleware の粗いゲート、最終的なオブジェクトレベル認可（所有・テナント検証）は DAL / Server Action 側（`ARCHITECTURE.md` S5/S6）。`source` にどちらで守るかを書く。

## `db-schema.json`

```jsonc
{
  "tables": [{
    "name": "Post",                    // [Next] Prisma モデル名
    "domain": "content",               // 主ドメイン（最も所有に近い）
    "accessedFrom": ["content", "admin", "api/feed"],  // [Next] このモデルを触る namespace 群（1 model : N namespace）
    "purpose": "投稿記事",
    "definedIn": "prisma/schema.prisma",
    "columns": [
      {"name": "id", "type": "Int", "pk": true, "notNull": true},
      {"name": "authorId", "type": "Int", "notNull": true, "fk": "User"}  // fk = 参照先モデル名
    ]
  }],
  "relations": [{"from": "Post", "to": "User"}],
  "notes": ["…"]
}
```

> [Next] **1 model : 1 route の写像を前提にしない**。実コードでは同一モデルが複数 namespace（feature / api group）から触られる（dogfood で 1 モデルが 5+ namespace から触られる例を検出）。`accessedFrom` でそれを表現し、`domain` は「最も所有に近い主ドメイン」とする。

## `db-indexes.json`（硬層が生成）

`adapters/extract-indexes.nextjs.js` の出力。`merge.js` が `tables[].idx` に合流させる。

```jsonc
{
  "Post": {
    "pk": ["id"],
    "fks": [{"cols": ["authorId"], "refTable": "User", "refCols": ["id"]}],
    "unique": [["slug"]],
    "index": [["authorId"], ["published"]]
  }
}
```

## `combined.json`（`merge.js` の出力 = HTML が読む `window.DATA`）

`domains[]` / `roles[]` / `endpointAuth[]` / `spaGuards[]` / `tables[]`（`idx` 付き）/ `relations[]` / `flowScreens[]` / `flowEdges[]` を1つに統合したもの。詳細は `merge.js` と `template.html`（`window.DATA` 利用箇所）を参照。

## 決定性の範囲

硬層（決定的・パーサが生成）と軟層（LLM・サブエージェントが生成）の線引きは `methodology.md` を参照。`db-indexes.json` は完全に硬層、`<domain>.json` の意味付け（purpose / gotchas）は軟層。
