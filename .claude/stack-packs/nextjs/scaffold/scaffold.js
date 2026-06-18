#!/usr/bin/env node
// scaffold.js — golden path skeleton を新規 PJ に展開する（generator）。
//
//   node scaffold.js <targetDir> [--force]
//
// `template/`（= 規約を満たす具体 vertical slice・feature=posts）をそのままコピーする。
// fitness-functions の conforming fixture と**同一ファイル**なので、出力は定義上 fitness green。
// `gitignore` → `.gitignore` にリネームして出力する（pack 内では dot なしで tracked 保管）。
//
// 注: feature 名のパラメタ置換（posts→任意）は camelCase 複合識別子の安全置換が要るため未実装。
//     現状は `posts` slice を「複製して新 feature を作る手本」として使う（README 参照）。

const fs = require('fs');
const path = require('path');

const TEMPLATE = path.resolve(__dirname, 'template');

function copyDir(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  for (const ent of fs.readdirSync(src, { withFileTypes: true })) {
    const from = path.join(src, ent.name);
    // pack 内テンプレの `gitignore` は出力時に `.gitignore` へ
    const outName = ent.name === 'gitignore' ? '.gitignore' : ent.name;
    const to = path.join(dst, outName);
    if (ent.isDirectory()) copyDir(from, to);
    else fs.copyFileSync(from, to);
  }
}

function main() {
  const args = process.argv.slice(2);
  const force = args.includes('--force');
  const target = args.find((a) => !a.startsWith('--'));

  if (!target) {
    console.error('usage: node scaffold.js <targetDir> [--force]');
    process.exit(2);
  }
  const dst = path.resolve(target);
  if (fs.existsSync(dst) && fs.readdirSync(dst).length > 0 && !force) {
    console.error(`✗ ${dst} は空ではありません（上書きは --force）`);
    process.exit(1);
  }

  copyDir(TEMPLATE, dst);

  console.log(`✓ golden path skeleton を展開しました: ${dst}`);
  console.log('');
  console.log('次の手順:');
  console.log('  1. <PACKAGE_MANAGER> install');
  console.log('  2. DATABASE_URL を .env に設定し prisma migrate dev');
  console.log('  3. `posts` slice（app/posts + lib/posts + lib/validations/post.ts）を');
  console.log('     手本に新しい feature を複製する（各層の規約はコメントに明記）');
  console.log('  4. アーキ検証: node .claude/stack-packs/nextjs/fitness-functions/run-fitness.js .');
  console.log('     （= npm run test:arch。golden path から逸脱すると error で落ちる）');
}

main();
