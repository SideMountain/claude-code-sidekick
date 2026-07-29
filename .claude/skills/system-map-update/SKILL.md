---
name: system-map-update
description: system-map（docs/visualization/system-map.html）の定期更新。硬層を enrich 保持で再生成し、差分だけ軟層 enrich → build → verify → 鮮度マーカー記録まで一貫実行する。構造変更のマージ後や /review の「🗺 地図が古い」nudge 時に実行。STACK_PACK 採用 PJ 向け。
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, Agent
---

# /system-map-update — システム地図の定期更新

`docs/visualization/` の system-map を現在のコードに追随させる。**軟層の enrich 資産
（purpose/summary/kind/gotchas/idempotency/解消済み uncertainties）を保持したまま**骨格だけ更新し、
差分だけ再 enrich する（全量やり直しをしない）。初回生成・仕組みの説明は `docs/visualization/README.md` を参照。

前提: `STACK_PACK` を採用し system-map を初回生成済みの PJ（`.claude/stack-packs/<pack>/skills/system-map/`）。

## 実行タイミング

- `/review` fast-gate が「🗺 地図が古い」と nudge したとき
- 機能追加・テーブル追加を含む PR をベースブランチにマージした後
- `/weekly-inventory` 等の定期棚卸しのついで（構造変更が溜まっていそうなとき）

## 手順

### Step 0: 前提確認

- 新規 Worktree で作業する（H12。docs のみの変更なので軽量パターン可・依存インストール不要）
- `docs/visualization/adapters/update-skeleton.js` の存在を確認。無ければ初回生成から（README 参照）

### Step 1: 骨格の再生成（決定的・無 LLM）

```bash
cd docs/visualization && node adapters/update-skeleton.js
```

末尾の差分レポートを読む:
- **差分なし** → Step 3 へ
- **新規 / 骨格変更 / 削除** が報告された → Step 2 へ

### Step 2: 差分だけ軟層 enrich

レポートされた項目**だけ**を対象に、該当ソースを読んで `data/*.json` を enrich する:

- 新規 screen: `kind`（list|form|detail|…）・`title`（日本語）
- 新規 api: `summary`（日本語1文）。webhook/cron なら `idempotency` 判定（event-id-dedup | provably-idempotent | unguarded）
- 新規 table: `domain`・`purpose`
- 骨格変更 api: 既存 `summary`/`gotchas` が現状と合っているか確認・修正
- 新規 uncertainty: ソースで解消できるものは解消して配列から除去（解消根拠は `notes`/`gotchas` へ）

**壊してはならないもの**: method / path / operationId / kind / trigger / dbTablesRead / dbTablesWrite /
validation（硬層の決定的出力）。JSON 構造・キー名。

差分が多い（目安 20 件超）場合はドメイン別に Agent へファンアウトする。各 Agent の Return Contract は
「enrich 完了件数 + 残 uncertainties の要旨」のみ（生の調査結果を返させない）。

編集後: `node -e "JSON.parse(require('fs').readFileSync('data/<file>','utf8'))"` で妥当性確認。

### Step 3: ビルド & 検証 & 鮮度マーカー

```bash
cd docs/visualization
PACK=../../.claude/stack-packs/nextjs   # STACK_PACK に合わせる
node $PACK/skills/system-map/assets/merge.js data combined.json
node $PACK/skills/system-map/assets/build.js $PACK/skills/system-map/assets/template.html combined.json system-map.html
node $PACK/skills/system-map/assets/verify.js system-map.html   # PASS 必須。FAIL なら該当 JSON を直して再ビルド
node $PACK/fitness-functions/canonical-counts.js ../.. > ../../.claude/.system-map-counts.json
```

### Step 4: コミット

`data/*.json`（と adapters に変更があればそれ）をコミットする（H15: 背景/対応/影響）。
`combined.json` / `system-map.html` / `.system-map-counts.json` は非追跡（.gitignore 済み）なので含めない。
push / PR はユーザー確認（H7/H8）。

## 出力フォーマット

```
🗺 system-map 更新完了
- 骨格差分: 新規 N / 変更 M / 削除 K（差分なしの場合はその旨）
- enrich: 対象 X 件を記入・uncertainty Y 件解消（Z 件残）
- verify: PASS / カウント: <canonical-counts の要約>
- コミット: <hash>（push/PR は要確認）
```

## Gotchas

- 素の硬層アダプタ（`adapters/extract-*.js`）を直接 `data/` に向けない — enrich が全消しされる。必ず update-skeleton.js 経由
- verify FAIL の典型は JSON 構文崩れ。`combined.json` を JSON として開いて特定する
- adapters が拾えない既知の限界（flow エッジ・RLS・UNIQUE/INDEX 等）は README「既知の限界」参照。enrich で無理に埋めない
