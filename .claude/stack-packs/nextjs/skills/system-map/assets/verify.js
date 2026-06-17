#!/usr/bin/env node
/* 汎用: 生成HTMLを自己検証。①埋め込みJSON ②アプリJS構文 ③DOMスタブで全ビュー描画。
 * 使い方: node verify.js [html=system-map.html] */
const fs = require('fs'), vm = require('vm');
const htmlPath = process.argv[2] || 'system-map.html';
const html = fs.readFileSync(htmlPath, 'utf8');
let ok = true; const fail = m => { ok = false; console.log('  x ' + m); }; const pass = m => console.log('  o ' + m);

console.log('[1] embedded data');
if (html.includes('__DATA__')) fail('placeholder __DATA__ remains'); else pass('placeholder replaced');
const m = html.match(/type="application\/json">([\s\S]*?)<\/script>/);
let DATA; try { DATA = JSON.parse(m[1].replace(/\\u003c/g, '<')); pass('embedded JSON parses'); }
catch (e) { fail('JSON parse: ' + e.message); process.exit(1); }

console.log('[2] app JS syntax');
const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(x => x[1]);
const app = scripts.find(s => s.includes('renderOverview'));
try { new Function(app); pass('app JS parses'); } catch (e) { fail('syntax: ' + e.message); }

console.log('[3] render all views (DOM stub)');
const el = () => ({ innerHTML: '', textContent: '', value: '', style: {}, dataset: {},
  classList: { toggle() {}, add() {}, remove() {}, contains() { return false } },
  addEventListener() {}, removeEventListener() {}, closest() { return null },
  querySelector() { return el(); }, querySelectorAll() { return []; }, appendChild() {}, setAttribute() {}, getAttribute() { return null } });
const appdataEl = { textContent: m[1] };
const doc = { getElementById: id => id === 'appdata' ? appdataEl : el(), querySelector: () => el(), querySelectorAll: () => [], createElement: () => el(), addEventListener() {} };
const sb = { document: doc, location: { hash: '#/overview' }, console, JSON, Math, Object, Array, Set, Map, String, Number, Boolean, encodeURIComponent, decodeURIComponent };
sb.window = sb; sb.globalThis = sb; sb.window.addEventListener = () => {}; sb.window.scrollTo = () => {};
const errors = [];
try { vm.runInNewContext(app, sb, { filename: 'app.js' }); pass('boot ok'); }
catch (e) { fail('boot: ' + e.message); process.exit(1); }

const norm = p => String(p || '').replace(/^(GET|POST|PUT|DELETE|PATCH)\s+/i, '').replace(/^\/+/, '').trim();
const hashes = ['#/overview', '#/domains', '#/screens', '#/apis', '#/tables', '#/roles', '#/flow', '#/er', '#/impact', '#/search/x'];
(DATA.domains || []).forEach(d => { hashes.push('#/domain/' + d.id); (d.screens || []).forEach(s => hashes.push('#/screen/' + d.id + '::' + (s.id || ''))); (d.apis || []).forEach(a => hashes.push('#/api/' + norm(a.path))); });
(DATA.tables || []).forEach(t => { hashes.push('#/table/' + t.name); hashes.push('#/er/' + encodeURIComponent(t.domain)); hashes.push('#/impact/table/' + t.name); });
[...new Set((DATA.flowScreens || []).filter(s => s.module).map(s => s.module))].forEach(mo => hashes.push('#/flow/' + encodeURIComponent(mo + '::*')));
let n = 0;
for (const h of hashes) { sb.location.hash = h; try { sb.route(); n++; } catch (e) { errors.push(h + ' -> ' + e.message); } }
if (errors.length) { fail(`rendered ${n}/${hashes.length}`); errors.slice(0, 20).forEach(e => console.log('    x ' + e)); }
else pass(`rendered ${n}/${hashes.length} routes, no runtime errors`);

console.log(ok ? '\nPASS' : '\nFAIL'); process.exit(ok ? 0 : 1);
