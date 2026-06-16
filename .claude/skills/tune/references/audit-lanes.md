# 監査レーンの実装（read-only 静的）

`/tune` Step 1-2 で Agent に渡す4レーンのプロンプト・findings schema・統合手順。
**すべて read-only**: Read / Grep / Glob / ファイルサイズ参照のみ。テストスイート実行・ビルド・DB接続・`.env` 接触は禁止。全ファイルを読まず、grep 密度とサイズでホットスポットを特定して必要箇所だけ読む。

---

## 偵察コマンド（Step 0・メインで実行）

```bash
PJ=<対象パス>
# stack
grep -oE '"(vitest|jest|@playwright/test|@testing-library/[a-z]+)"' "$PJ/package.json" 2>/dev/null
grep -E '"(test|test:coverage|test:e2e|build|lint|typecheck)"' "$PJ/package.json" 2>/dev/null
ls "$PJ/.github/workflows/" 2>/dev/null
# 規模（node_modules / .git 除外）
find "$PJ" -path '*/node_modules' -prune -o -name '*.test.*' -print -o -name '*.spec.*' -print 2>/dev/null | grep -vE '/node_modules/|/\.git/' | wc -l
# E2E 本数・テストLOC・srcLOC は find + wc で概算（playwright/e2e ディレクトリ）
```

PM が pnpm/yarn なら `npm` を読み替え。Python は pytest/`pyproject.toml`・`tests/` で同様に偵察。

---

## 共通ガード文（各レーンプロンプト冒頭に付ける）

```
READ-ONLY STATIC ANALYSIS. Target: <PJパス>.
禁止: ファイルの編集/作成、テストスイート/ビルド/PM コマンドの実行、.env 読取/変更、DB/ネットワーク接続。
許可: Read / Grep / Glob / ファイルサイズ（wc・ls）のみ。
全ファイルを読まない。grep のヒット密度 + ファイルサイズで最悪ホットスポットを特定し、そこだけ読む。
これは利用者の業務コード。何も変更しない。
偵察ベースライン: <Step 0 の数値（テストファイル数・E2E数・テスト/src LOC・stack）>
```

---

## ① テスト実行の高速化（最重要指標）

```
Lane ① テスト実行の高速化。unit/integration スイートを遅くする静的シグナルを洗い出す（E2E は除外）。
探索: 直列実行を強制する設定（vitest fileParallelism:false / maxWorkers 等）・pool 設定の有無・
  test.concurrent / describe.concurrent の不在 / 実時間待ち（setTimeout/sleep/await new Promise が fake timers なし）/
  重い beforeEach・全ツリー render の反復 / 巨大テストファイル（500 LOC 超）/ unit への実 IO・network 混入 /
  カバレッジ計測の常時実行（重い reporter=html 等）。
各 finding: locations(file:pattern) / evidence(件数) / 具体的な高速化案 / risk / gated（設定のみ=false）。
壁時計影響の大きい順。
```

## ② CI高速化（テスト削除ゼロの純利益）

```
Lane ② CI高速化。.github/workflows/ を読む。テストを減らさず CI 時間を縮める機会:
  ジョブ並列化（直列の lint→test→build を分割）/ test sharding（matrix）/ affected・changed-since 実行 /
  依存キャッシュ・install 方式（npm install→npm ci 等）・Playwright ブラウザキャッシュ・.next/cache /
  build の二重実行 / fail-fast / 集約ゲート（required check 安定化）の有無。
各 finding: 現状の証拠（yml 引用）/ 変更案 / 期待効果 / risk / gated。
⚠ shard・ジョブ増は CI minutes を増やす → gated=false でも「分↑」と明記し cost↔time を出す。
```

## ③ テスト棚卸し（見直し・削除しない・SUGGEST-ONLY）

```
Lane ③ テスト棚卸し。低価値・冗長なテストの臭いを FLAG する。安全網の削除は絶対に提案しない。
  真の重複（同一モジュールを別ファイルで二重テスト・コピペ）/ アサーション無し・トートロジー
  （expect 無し・getBy().toBeDefined()/toBeTruthy() など常に真）/ 実装結合で脆い（内部実装・class名直アサート・
  snapshot 乱用・過剰 spy）/ モック定義の横断コピペ。jest-dom 等の導入有無も確認。
E2E/integration/regression は対象外（完全除外）。
各 suggestion は「統合 / リファクタ / quarantine / 補強 / 格上げ」のいずれか — delete 禁止。全て gated=true。
```

## ④ コード共通化・単純化（挙動保存）

```
Lane ④ コード健全性。src（テスト以外）の挙動保存リファクタ機会:
  重複ロジック/コンポーネント/hook（バイト一致は最優先）/ 巨大ファイル（400-500 LOC 超）/
  高複雑度・深いネスト（早期 return/抽出で平坦化可）/ コピペされた定数・モーダル/ダイアログ足場 /
  認証ボイラープレートの共通 guard 不在（認可漏れを構造で防ぐ余地）。
生成コード（決定木・自動生成物）は対象外（手で触らない）と明記。
各 finding: locations / evidence(サイズ/件数) / 挙動保存の具体案(extract/共通化/平坦化) / risk / gated=true。
```

---

## findings schema（各レーン）

```json
{
  "lane": "string",
  "summary": "2-3文の総括",
  "findings": [{
    "title": "string", "severity": "high|medium|low",
    "locations": ["file:line"], "evidence": "定量根拠",
    "suggestion": "是正案（テスト削除は禁止）", "risk": "string",
    "gated": "boolean (true=コード/テスト変更=worktree+PR+green+人手OK / false=設定のみの純利益)"
  }]
}
```

---

## 統合（Step 2）

HARD ガードレール（`safety-guardrails.md`）を強制した上で1本のレポートに統合する:

- 優先度は**高速化ファースト**: ① + ②（純利益が集中）→ ③ → ④
- **純利益(gated=false)** と **要ゲート(gated=true)** を明確に分離
- **削除提案ゼロ**を最終検証（1件でもあれば統合/補強に変換）
- cost↔time: 分を増やす施策に注記

### レポート構成

```
## 要約（検証済み事実 + 最大レバーの所在）
## ① テスト実行の高速化（最重要）  — 純利益 / 要ゲート
## ② CI高速化  — 純利益 / 要ゲート
## ③ テスト棚卸し（見直し・削除しない）
## ④ コード共通化・単純化
## 安全制約（削除提案ゼロ / E2E除外 / mutation不使用 / 夜間ループ対象外 を明記）
```

横断トップN（rank / title / lane / impact / risk / gated）も出す。
