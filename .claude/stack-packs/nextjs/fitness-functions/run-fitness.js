#!/usr/bin/env node
// run-fitness.js — architecture fitness 関数の CLI ランナー（検知層）。
//
//   node run-fitness.js [projectRoot]   既定 = カレント
//
// error が 1 件でもあれば exit 1（CI を落とす）。warn は可視化のみで落とさない。
// 単一 Node プロセス（WSL の vitest worker hang を回避）。下流の package.json:
//   "test:arch": "node .claude/stack-packs/nextjs/fitness-functions/run-fitness.js ."

const path = require('path');
const { runAll } = require('./checks');
const { canonicalCounts } = require('./lib/route-enumerator');

function main() {
  const root = path.resolve(process.argv[2] || '.');
  const results = runAll(root);

  let errors = 0;
  let warns = 0;
  const lines = [];

  for (const r of results) {
    const errs = r.findings.filter((x) => x.severity === 'error');
    const wns = r.findings.filter((x) => x.severity === 'warn');
    errors += errs.length;
    warns += wns.length;
    const status = errs.length ? 'FAIL' : wns.length ? 'warn' : 'ok';
    lines.push(`[${status.toUpperCase().padEnd(4)}] ${r.rule} ${r.title}${r.info ? `  (mutation 面 ${r.info.mutationSurface})` : ''}`);
    for (const x of [...errs, ...wns]) {
      lines.push(`        ${x.severity === 'error' ? '✗' : '·'} ${x.file}:${x.line}  ${x.message}`);
    }
  }

  const counts = canonicalCounts(root);
  lines.push('');
  lines.push(`正準カウント: route ${counts.routeEntries} entry (${counts.routeFiles} files) / screen ${counts.screens} / server-action ${counts.serverActions} / cron ${counts.crons} / webhook ${counts.webhooks} / mutation 面 ${counts.mutationSurface}`);
  lines.push(`結果: error ${errors} / warn ${warns}`);

  process.stdout.write(lines.join('\n') + '\n');
  process.exit(errors ? 1 : 0);
}

main();
