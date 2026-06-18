#!/usr/bin/env node
// verify.js — fitness 関数の自己検証（pack の CI / pre-PR で回す）。
//
//   1. conforming fixture（= scaffold/template = golden slice）に対し runAll → error 0 を保証
//      （false-positive が無いこと。scaffold 出力 ≡ この fixture なので「生成器が規約を満たす」証明も兼ねる）
//   2. 各 violation fixture に対し runAll → 対象ルールが期待 severity を 1 件以上出すことを保証
//      （false-negative が無いこと。各 check が本当に違反を捕まえる証明）
//
// 単一 Node プロセス（system-map verify.js と同じ規律・WSL 安全）。

const path = require('path');
const { runAll } = require('./checks');
const { canonicalCounts } = require('./lib/route-enumerator');

const HERE = __dirname;
const CONFORMING = path.resolve(HERE, '../scaffold/template');
const FIX = path.resolve(HERE, 'fixtures/violations');

// 各 violation fixture で「赤」を出すべきルールと、その期待 severity。
const EXPECT = {
  s1: { rule: 'S1', severity: 'error' },
  s2: { rule: 'S2', severity: 'error' },
  s3: { rule: 'S3', severity: 'error' },
  s4: { rule: 'S4', severity: 'error' },
  s5: { rule: 'S5', severity: 'error' },
  s6: { rule: 'S6', severity: 'warn' },  // object-level: 存在=HARD だが網羅=SOFT → warn
  s7: { rule: 'S7', severity: 'error' },
  h1: { rule: 'H1', severity: 'error' },
  h3: { rule: 'H3', severity: 'warn' },  // rendering SHOULD
  h4: { rule: 'H4', severity: 'error' }, // .backup は error
  // 敵対的 fixtures（レビュー由来の回帰防止）
  's4-col0': { rule: 'S4', severity: 'error' },    // col-0 inline 'use server'
  's4-inline': { rule: 'S4', severity: 'error' },  // 同一行 inline closure
  'strip-regex': { rule: 'S5', severity: 'error' }, // URL 正規表現の // が同一行違反を潰さない
};

// 正準カウントが凍結定義どおりか（inline / データ const を action と数えない）
const COUNT_CASES = [
  { dir: 's4-col0', field: 'serverActions', expect: 0 },   // inline は action でない
  { dir: 's4-inline', field: 'serverActions', expect: 0 },
  { dir: 'sa-const', field: 'serverActions', expect: 1 },  // MAX は数えない・関数 1 つ
];

let failed = 0;
const log = (s) => process.stdout.write(s + '\n');

// --- 1. conforming = error 0 ---
const conf = runAll(CONFORMING);
const confErrors = conf.flatMap((r) => r.findings.filter((x) => x.severity === 'error').map((x) => ({ rule: r.rule, ...x })));
const confWarns = conf.flatMap((r) => r.findings.filter((x) => x.severity === 'warn'));
if (confErrors.length === 0) {
  log(`PASS  conforming (scaffold/template): error 0  (warn ${confWarns.length})`);
} else {
  failed++;
  log(`FAIL  conforming (scaffold/template): error ${confErrors.length}（false-positive）`);
  for (const e of confErrors) log(`        ✗ ${e.rule} ${e.file}:${e.line} ${e.message}`);
}

// --- 2. 各 violation fixture でルール発火 ---
for (const [dir, exp] of Object.entries(EXPECT)) {
  const root = path.join(FIX, dir);
  const results = runAll(root);
  const r = results.find((x) => x.rule === exp.rule);
  const hits = r ? r.findings.filter((x) => x.severity === exp.severity) : [];
  if (hits.length >= 1) {
    log(`PASS  violations/${dir}: ${exp.rule} fired ${exp.severity} ×${hits.length}`);
  } else {
    failed++;
    log(`FAIL  violations/${dir}: ${exp.rule} が ${exp.severity} を出さなかった（false-negative）`);
  }
}

// --- 2.5. false-positive 回帰（正当コードを error にしない・dogfood 由来） ---
const FALSEPOS = [
  { dir: 'h1-existence', rule: 'H1' }, // DATABASE_URL の存在チェック / ラベルログは error にしない
];
for (const c of FALSEPOS) {
  const root = path.resolve(HERE, 'fixtures/falsepos', c.dir);
  const r = runAll(root).find((x) => x.rule === c.rule);
  const errs = r ? r.findings.filter((x) => x.severity === 'error') : [];
  if (errs.length === 0) {
    log(`PASS  falsepos/${c.dir}: ${c.rule} error 0（誤検知なし）`);
  } else {
    failed++;
    log(`FAIL  falsepos/${c.dir}: ${c.rule} が error ${errs.length} 件（false-positive）`);
  }
}

// --- 3. 正準カウントが凍結定義どおり ---
for (const c of COUNT_CASES) {
  const counts = canonicalCounts(path.join(FIX, c.dir));
  if (counts[c.field] === c.expect) {
    log(`PASS  count ${c.dir}: ${c.field}=${counts[c.field]}`);
  } else {
    failed++;
    log(`FAIL  count ${c.dir}: ${c.field}=${counts[c.field]}（expected ${c.expect}・凍結定義から drift）`);
  }
}

log('');
if (failed) {
  log(`✗ verify FAILED: ${failed} 件`);
  process.exit(1);
}
log('✓ verify PASS: conforming=green / 全 violation fixture で該当ルール発火 / 正準カウント凍結');
