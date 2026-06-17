#!/usr/bin/env node
/* Prisma schema (schema.prisma) から PK / FK / UNIQUE / INDEX を決定的抽出 (無LLM) → db-indexes.json
 * 硬い層パーサ: LLM 不要。schema.prisma を読むだけで冪等にインデックス情報が出る。
 * 使い方: node extract-indexes.nextjs.js [schema=prisma/schema.prisma] [out=data/db-indexes.json]
 * 出力形: { ModelName: { pk:[col], fks:[{cols,refTable,refCols}], unique:[[col]], index:[[col]] } }
 *   - この形は merge.js が tables[].idx に合流させ、template.html が ER / テーブル詳細で描画する。
 *   - 複数 datasource / multiSchema には未対応（単一 schema.prisma 前提）。 */
const fs = require('fs'), path = require('path');
const schemaPath = process.argv[2] || 'prisma/schema.prisma';
const outPath = process.argv[3] || path.join('data', 'db-indexes.json');

const src = fs.readFileSync(schemaPath, 'utf8');
const clean = src.replace(/\/\/[^\n]*/g, '');                       // strip line comments
const cols = s => s.split(',').map(x => x.trim().replace(/["'\[\]]/g, '')).filter(Boolean);

const T = {};
const modelRe = /model\s+(\w+)\s*\{([\s\S]*?)\}/g;
let mm;
while ((mm = modelRe.exec(clean))) {
  const name = mm[1], body = mm[2];
  const t = T[name] = { pk: [], fks: [], unique: [], index: [] };
  const lines = body.split('\n').map(l => l.trim()).filter(Boolean);
  for (const ln of lines) {
    let m;
    // block-level attributes (@@id / @@unique / @@index)
    if (m = ln.match(/@@id\s*\(\s*\[([^\]]+)\]/)) { t.pk = cols(m[1]); continue; }
    if (m = ln.match(/@@unique\s*\(\s*\[([^\]]+)\]/)) { t.unique.push(cols(m[1])); continue; }
    if (m = ln.match(/@@index\s*\(\s*\[([^\]]+)\]/)) { t.index.push(cols(m[1])); continue; }
    if (ln.startsWith('@@')) continue;
    // field line: name Type[]? attrs...
    const fm = ln.match(/^(\w+)\s+([A-Za-z_]\w*)(\[\])?(\?)?\s*(.*)$/);
    if (!fm) continue;
    const fname = fm[1], ftype = fm[2], attrs = fm[5] || '';
    if (/@id\b/.test(attrs)) t.pk = [fname];
    if (/@unique\b/.test(attrs)) t.unique.push([fname]);
    // owning side of a relation: @relation(fields: [...], references: [...]) → FK cols, ftype = referenced model
    const rel = attrs.match(/@relation\s*\([^)]*fields:\s*\[([^\]]+)\][^)]*references:\s*\[([^\]]+)\]/);
    if (rel) t.fks.push({ cols: cols(rel[1]), refTable: ftype, refCols: cols(rel[2]) });
  }
}
// drop UNIQUE rows that merely duplicate the PK
Object.values(T).forEach(t => {
  const pk = t.pk.join(',').toLowerCase();
  t.unique = t.unique.filter(u => u.join(',').toLowerCase() !== pk);
});

fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, JSON.stringify(T, null, 1));

const n = Object.keys(T).length;
let pk = 0, fk = 0, uq = 0, ix = 0;
Object.values(T).forEach(t => { if (t.pk.length) pk++; fk += t.fks.length; uq += t.unique.length; ix += t.index.length; });
console.log('models:', n, '| PK tables:', pk, ' FKs:', fk, ' UNIQUE:', uq, ' INDEX:', ix);
console.log('-> ' + outPath);
