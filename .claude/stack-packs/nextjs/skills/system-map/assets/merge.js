#!/usr/bin/env node
/* 汎用: data/*.json を形で自動判別して単一モデル combined.json に統合する。
 * 使い方: node merge.js [dataDir=./data] [out=./combined.json]
 * 出力モデルの形は schema.md / template.html(window.DATA) を参照。 */
const fs = require('fs'), path = require('path');
const dataDir = process.argv[2] || 'data';
const outPath = process.argv[3] || 'combined.json';
const files = fs.readdirSync(dataDir).filter(f => f.endsWith('.json'));
const read = f => JSON.parse(fs.readFileSync(path.join(dataDir, f), 'utf8'));
const issues = [];

let perms = {}, db = {}, dbIdx = {};
const domains = [], flowScreensRaw = [], flowEdgesRaw = [];
for (const f of files) {
  let j; try { j = read(f); } catch (e) { issues.push(`PARSE FAIL ${f}: ${e.message}`); continue; }
  const base = f.toLowerCase();
  if (base === 'permissions.json') { perms = j; continue; }
  if (base === 'db-schema.json') { db = j; continue; }
  if (base === 'db-indexes.json') { dbIdx = j; continue; }
  if (base === 'combined.json') continue;
  if (Array.isArray(j.screens) && Array.isArray(j.edges) && !j.domains && !j.apis) { // flow file
    j.screens.forEach(s => flowScreensRaw.push(s)); j.edges.forEach(e => flowEdgesRaw.push(e)); continue;
  }
  const arr = Array.isArray(j.domains) ? j.domains : (j.id ? [j] : []);
  arr.forEach(d => { d.screens = d.screens || []; d.apis = d.apis || []; domains.push(d); });
}

// db indexes -> attach to tables
const idxByLower = {}; Object.entries(dbIdx).forEach(([k, v]) => idxByLower[k.toLowerCase()] = v);
(db.tables || []).forEach(t => {
  const v = idxByLower[String(t.name).toLowerCase()];
  if (v) { const pk = (v.pk || []).join(',').toLowerCase(); v.unique = (v.unique || []).filter(u => u.join(',').toLowerCase() !== pk); t.idx = v; }
});

// flow normalize: dedupe screens, alias, drop history-back, synth external
const fsById = {};
flowScreensRaw.forEach(s => {
  if (!fsById[s.id]) fsById[s.id] = s;
  else { const e = fsById[s.id]; ['title','path','component','kind','domain','module'].forEach(k => { if (!e[k] && s[k]) e[k] = s[k]; });
    e.displays = [...new Set([...(e.displays||[]), ...(s.displays||[])])]; e.elements = [...(e.elements||[]), ...(s.elements||[])]; e.entry = e.entry || s.entry; }
});
const flowAlias = {}; // 任意: 画面IDの別名統合マップ（例 {'home_top':'home'}）。既定は別名なし
const flowScreens = Object.values(fsById);
const fsIds = new Set(flowScreens.map(s => s.id));
const flowEdges = []; const synth = {};
for (const e of flowEdgesRaw) {
  let from = flowAlias[e.from] || e.from, to = flowAlias[e.to] || e.to;
  if (!to || !from || to === '(previous)' || from === '(previous)') continue;
  [from, to].forEach(id => { if (!fsIds.has(id) && !synth[id]) synth[id] = { id, title: id, kind: 'external', _external: true, module: '', domain: '' }; });
  flowEdges.push({ from, to, trigger: e.trigger || '', condition: e.condition || '' });
}
Object.values(synth).forEach(s => flowScreens.push(s));

const model = {
  generatedAt: null, // stamp後付け
  domains,
  roles: perms.roles || [], endpointAuth: perms.endpointAuth || [], spaGuards: perms.spaGuards || [],
  userTypeToPermission: perms.userTypeToPermission || [], permNotes: perms.notes || [], permUncertainties: perms.uncertainties || [],
  tables: db.tables || [], relations: db.relations || [], dbNotes: db.notes || [], dbUncertainties: db.uncertainties || [],
  flowScreens, flowEdges,
};
fs.writeFileSync(outPath, JSON.stringify(model));

console.log('=== MERGE ===');
console.log('domains   :', domains.length, '|', domains.map(d => d.id).join(', '));
console.log('apis      :', domains.reduce((n, d) => n + (d.apis || []).length, 0));
console.log('screens   :', domains.reduce((n, d) => n + (d.screens || []).length, 0));
console.log('roles     :', model.roles.length, '| authGroups:', model.endpointAuth.length);
console.log('tables    :', model.tables.length, '| withIdx:', model.tables.filter(t => t.idx).length, '| relations:', model.relations.length);
console.log('flow      :', flowScreens.length, 'screens /', flowEdges.length, 'edges (synth', Object.keys(synth).length, ')');
if (issues.length) { console.log('--- ISSUES ---'); issues.forEach(i => console.log(' ', i)); }
console.log('-> ' + outPath, fs.statSync(outPath).size, 'bytes');
