#!/usr/bin/env node
// scaffold.js — golden path skeleton を新規 PJ に展開する（generator）。
//
//   node scaffold.js <targetDir> [--force]
//
// `template/`（= 規約を満たす具体 vertical slice・feature=posts）をそのままコピーする。
// fitness-functions の conforming fixture と**同一ファイル**なので、出力は定義上 fitness green。
// `gitignore` → `.gitignore` にリネームして出力する（pack 内では dot なしで tracked 保管）。
//
// **オーバーレイ前提**: pack は Next アプリ本体を作らない（先に `create-next-app` 等で土台を用意）。
// その土台の上に展開するため、既存ディレクトリには `--force` が要る。`package.json` だけは
// 破壊的に上書きせず**非破壊マージ**する（既存の name / version / 解決済み依存バージョンを保持し、
// golden path の script〔test:arch 等〕と不足依存〔@prisma/client・zod・server-only・prisma〕を足す）。
// その他 config（tsconfig/next.config/eslint/.gitignore/layout）は golden path 版で上書きする（同形・意図的）。
//
// 注: feature 名のパラメタ置換（posts→任意）は camelCase 複合識別子の安全置換が要るため未実装。
//     現状は `posts` slice を「複製して新 feature を作る手本」として使う（README 参照）。

const fs = require('fs');
const path = require('path');

const TEMPLATE = path.resolve(__dirname, 'template');

// create-next-app の既定ファイルで golden path に含まれないもの（残すと余分な screen "/" になる）。
const CNA_LEFTOVERS = ['app/page.tsx', 'app/globals.css'];
// template は next.config.ts / eslint.config.mjs を出力する。別形式が残ると config 二重定義になる。
const DUP_CONFIGS = ['next.config.js', 'next.config.mjs', 'eslint.config.js', 'eslint.config.ts'];

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

// 既存 package.json（create-next-app 等）と template の golden package.json を非破壊マージ。
// 既存の値が常に優先（name/version/依存バージョンを保持）し、template 側は**不足分だけ**足す。
function mergePackageJson(prior, tpl) {
  return {
    ...prior,
    scripts: { ...tpl.scripts, ...prior.scripts },
    dependencies: { ...tpl.dependencies, ...prior.dependencies },
    devDependencies: { ...tpl.devDependencies, ...prior.devDependencies },
  };
}

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
    console.error(`✗ ${dst} は空ではありません（create-next-app 等の土台に重ねるには --force）`);
    process.exit(1);
  }

  // 既存 package.json を copy 前に退避（copyDir が template 版で上書きするため）。
  const dstPkgPath = path.join(dst, 'package.json');
  let priorPkg = null;
  if (fs.existsSync(dstPkgPath)) {
    try {
      priorPkg = readJson(dstPkgPath);
    } catch {
      console.error(`✗ 既存 package.json が不正な JSON です: ${dstPkgPath}（修正してから再実行）`);
      process.exit(1);
    }
  }

  copyDir(TEMPLATE, dst);

  let merged = false;
  if (priorPkg) {
    const tplPkg = readJson(dstPkgPath); // = いま copy した template 版
    fs.writeFileSync(dstPkgPath, JSON.stringify(mergePackageJson(priorPkg, tplPkg), null, 2) + '\n');
    merged = true;
  }

  console.log(`✓ golden path skeleton を展開しました: ${dst}`);
  if (merged) {
    console.log('  ℹ 既存 package.json を非破壊マージしました（name / 既存依存バージョンを保持し、test:arch 等を追加）');
  }

  const leftovers = CNA_LEFTOVERS.filter((f) => fs.existsSync(path.join(dst, f)));
  if (leftovers.length) {
    console.log('');
    console.log('⚠ create-next-app の既定ファイルが残っています（golden path 外・layout は CSS を import しない）:');
    leftovers.forEach((f) => console.log(`    ${f}`));
    console.log('    → 削除するか app/page.tsx は /posts へのリダイレクトに置換してください');
    console.log('      （残すと fitness の screen 数 / system-map に余分な画面 "/" として出ます）');
  }

  const dupConfigs = DUP_CONFIGS.filter((f) => fs.existsSync(path.join(dst, f)));
  if (dupConfigs.length) {
    console.log('');
    console.log('⚠ golden path 版と別形式の config が共存しています（二重定義になります）:');
    dupConfigs.forEach((f) => console.log(`    ${f}  ← 削除推奨（pack は next.config.ts / eslint.config.mjs を使う）`));
  }

  console.log('');
  console.log('次の手順:');
  console.log('  1. <PACKAGE_MANAGER> install');
  console.log('  2. DATABASE_URL を .env に設定し prisma migrate dev（schema は posts slice 同梱・拡張する）');
  console.log('  3. `posts` slice（app/posts + lib/posts + lib/validations/post.ts）を');
  console.log('     手本に新しい feature を複製する（各層の規約はコメントに明記）');
  console.log('  4. アーキ検証: node .claude/stack-packs/nextjs/fitness-functions/run-fitness.js .');
  console.log('     （= npm run test:arch。golden path から逸脱すると error で落ちる）');
  console.log('  5. 可視化: system-map スキルを起動し、画面↔API↔DB↔権限↔遷移の地図を生成');
}

main();
