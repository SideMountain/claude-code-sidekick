#!/usr/bin/env node
/* Prisma schema (schema.prisma) から テーブル定義（列・型・PK・FK・リレーション）を決定的抽出 (無LLM) → db-schema.json
 * 硬い層パーサ: LLM 不要。schema.prisma を読むだけで冪等にスキーマの「形」が出る。
 *   - db-indexes.nextjs.js が PK/FK/UNIQUE/INDEX（索引視点）を出すのに対し、本 adapter は
 *     列・型・リレーションの「テーブル視点」を出す（schema.md の db-schema.json 契約）。両者は相補。
 *   - `accessedFrom`（1 model : N namespace）は app/lib を grep して `prisma.<model>.` の出現 namespace を集める（硬寄り）。
 *   - `domain`（主ドメイン）・`purpose` は意味付け＝軟層に委ねる（空で出す）。
 * 使い方: node extract-schema.nextjs.js [root=.] [out=data/db-schema.json] [schema=<root>/prisma/schema.prisma]
 * 出力形: schema.md の `db-schema.json`（{ tables:[{name,domain,accessedFrom,purpose,definedIn,columns:[{name,type,pk,notNull,fk}]}], relations, notes, uncertainties }） */
const fs = require('fs'), path = require('path');
const { walk, read } = require('../../../../fitness-functions/lib/fs-util');

const root = process.argv[2] || '.';
const outPath = process.argv[3] || path.join('data', 'db-schema.json');
const schemaPath = process.argv[4] || path.join(root, 'prisma', 'schema.prisma');

const SCALARS = new Set(['String', 'Boolean', 'Int', 'BigInt', 'Float', 'Decimal', 'DateTime', 'Json', 'Bytes']);

const src = fs.readFileSync(schemaPath, 'utf8');
const clean = src.replace(/\/\/[^\n]*/g, ''); // strip line comments（block コメントは Prisma に無い）

// pass 1: enum 名と model 名を集める（型がスカラ/enum/relation のどれかを判定するため）
const enums = new Set();
for (const m of clean.matchAll(/enum\s+(\w+)\s*\{/g)) enums.add(m[1]);
const modelNames = new Set();
for (const m of clean.matchAll(/model\s+(\w+)\s*\{/g)) modelNames.add(m[1]);
const isColumnType = (t) => SCALARS.has(t) || enums.has(t);

const definedInRel = path.relative(root, schemaPath).split(path.sep).join('/') || 'prisma/schema.prisma';

const tables = [];
const relations = [];
const modelRe = /model\s+(\w+)\s*\{([\s\S]*?)\}/g;
let mm;
while ((mm = modelRe.exec(clean))) {
  const name = mm[1], body = mm[2];
  const columns = [];
  let blockPk = null; // @@id([...]) → 複合 PK
  const fkByField = {}; // scalarField -> refModel（@relation の fields から）
  const lines = body.split('\n').map((l) => l.trim()).filter(Boolean);

  // @relation を body 全体で走査（multiline 対応・fields/references 順不同・#9/#10）。
  // フィールド宣言と @relation( の開始は同一行（[^\n]*?）、引数だけ複数行可（[\s\S]*?）。
  for (const rm of body.matchAll(/(\w+)[ \t]+(\w+)(?:\[\])?\??[^\n]*?@relation\s*\(([\s\S]*?)\)/g)) {
    const refModel = rm[2], grp = rm[3];
    const fm = grp.match(/fields:\s*\[([^\]]+)\]/);
    const rf = grp.match(/references:\s*\[([^\]]+)\]/);
    if (!fm || !rf) continue; // owning side（fields+references 両方）のみ。暗黙多対多・逆側は skip
    fm[1].split(',').map((s) => s.trim().replace(/["']/g, '')).filter(Boolean).forEach((f) => { fkByField[f] = refModel; });
    relations.push({ from: name, to: refModel });
  }

  for (const ln of lines) {
    let m;
    if ((m = ln.match(/@@id\s*\(\s*\[([^\]]+)\]/))) { blockPk = m[1].split(',').map((s) => s.trim().replace(/["']/g, '')); continue; }
    if (ln.startsWith('@@')) continue;
    const fm = ln.match(/^(\w+)\s+([A-Za-z_]\w*)(\[\])?(\?)?\s*(.*)$/);
    if (!fm) continue;
    const fname = fm[1], ftype = fm[2], isArray = !!fm[3], optional = !!fm[4], attrs = fm[5] || '';
    // relation ナビゲーション（model 型 / model[]）は DB 列ではないのでスキップ
    if (!isColumnType(ftype) || isArray) continue;
    const col = { name: fname, type: ftype };
    if (/@id\b/.test(attrs)) col.pk = true;
    col.notNull = !optional;
    if (fkByField[fname]) col.fk = fkByField[fname];
    columns.push(col);
  }
  if (blockPk) columns.forEach((c) => { if (blockPk.includes(c.name)) c.pk = true; });

  tables.push({ name, domain: '', accessedFrom: [], purpose: '', definedIn: definedInRel, columns });
}

// accessedFrom: app/lib を grep し `prisma.<modelCamel>.` の出現 namespace（ファイルの所属 dir）を集める（硬寄り）
const camel = (s) => s.charAt(0).toLowerCase() + s.slice(1);
const accessByModel = {}; // model -> Set(namespace)
const scanDirs = ['app', 'src/app', 'lib', 'src/lib', 'components', 'src/components']
  .map((d) => path.join(root, d)).filter((d) => fs.existsSync(d));
const seen = new Set();
for (const dir of scanDirs) {
  for (const file of walk(dir, (_f, n) => /\.(ts|tsx|js|jsx)$/.test(n))) {
    if (seen.has(file)) continue;
    seen.add(file);
    const code = read(file);
    const ns = path.dirname(path.relative(root, file)).split(path.sep).join('/');
    for (const t of tables) {
      const re = new RegExp('prisma\\.' + camel(t.name) + '\\.', 'g');
      if (re.test(code)) { (accessByModel[t.name] = accessByModel[t.name] || new Set()).add(ns); }
    }
  }
}
tables.forEach((t) => { if (accessByModel[t.name]) t.accessedFrom = [...accessByModel[t.name]].sort(); });

// relations 重複除去
const relKey = (r) => r.from + '->' + r.to;
const relSeen = new Set();
const relOut = relations.filter((r) => { const k = relKey(r); if (relSeen.has(k)) return false; relSeen.add(k); return true; });

const model = { tables, relations: relOut, notes: [], uncertainties: [] };
fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, JSON.stringify(model, null, 1));

console.log('tables:', tables.length, '| relations:', relOut.length,
  '| cols:', tables.reduce((n, t) => n + t.columns.length, 0),
  '| withAccess:', tables.filter((t) => t.accessedFrom.length).length);
console.log('-> ' + outPath);
