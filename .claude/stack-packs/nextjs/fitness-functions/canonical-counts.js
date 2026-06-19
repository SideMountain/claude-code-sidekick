#!/usr/bin/env node
/* 正準カウント（route/screen/server-action/cron/mutation 面）を JSON で出力する極小 CLI。
 * 正準 enumerator（lib/route-enumerator.js）の単一定義をそのまま使う（fitness / system-map と母集合一致）。
 *
 * 2 つの用途で共有する:
 *   1) system-map 生成時の「鮮度マーカー」書き出し:  node canonical-counts.js <root> > .claude/.system-map-counts.json
 *   2) /review の drift 検知（地図が古いかの 1 行通知・生成はしない）:
 *        node canonical-counts.js --drift <snapshot.json> [root]
 *        → 現在のカウントが snapshot と異なれば 1 行を stdout に出す（同じ or snapshot 無し → 沈黙）。
 *
 * 無 LLM・無 DB・即終（軽さドクトリン: 自動化は決定的・安いものだけ）。
 */
const fs = require('fs');
const { canonicalCounts } = require('./lib/route-enumerator');

const args = process.argv.slice(2);

if (args[0] === '--drift') {
  const snapPath = args[1];
  const root = args[2] || '.';
  const now = canonicalCounts(root);
  let old;
  try { old = JSON.parse(fs.readFileSync(snapPath, 'utf8')); } catch { process.exit(0); } // snapshot 無し → 沈黙
  const labels = {
    routeEntries: 'routes', screens: 'screens', serverActions: 'actions',
    crons: 'crons', mutationSurface: 'mutations', webhooks: 'webhooks',
  };
  const diffs = [];
  for (const k of Object.keys(labels)) {
    const o = old[k], n = now[k];
    if (o !== n) diffs.push(`${labels[k]} ${o === undefined ? '?' : o}→${n}`);
  }
  if (diffs.length) {
    process.stdout.write('🗺 system-map drift: ' + diffs.join(', ') + ' → 影響調査/レビュー前に /system-map 再生成を推奨\n');
  }
  process.exit(0);
}

process.stdout.write(JSON.stringify(canonicalCounts(args[0] || '.')) + '\n');
