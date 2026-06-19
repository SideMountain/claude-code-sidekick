#!/usr/bin/env node
/* 画面遷移の骨格を決定的抽出 (無LLM) → flow-structure.json（merge.js が flow ファイルとして食う {screens[],edges[]}）。
 *
 * 硬寄り: 静的な遷移（`<Link href>` / `router.push|replace` / `redirect|permanentRedirect`）を grep し、
 *   from = その遷移を含むファイルが属する画面（最近接の page 祖先）、to = 遷移先 route の画面 id とする。
 *   遷移先に page が無ければ merge.js が external ノードを合成する。
 * SOFT 残差: 対話的 leaf の動的遷移（テンプレートリテラル補間・実行時計算 href）は拾えない → uncertainties。
 *
 * 使い方: node extract-links.nextjs.js [root=.] [out=data/flow-structure.json] */
const fs = require('fs'), path = require('path');
const en = require('../../../../fitness-functions/lib/route-enumerator');
const { walk, read, stripComments, resolveAppDir } = require('../../../../fitness-functions/lib/fs-util');

const root = process.argv[2] || '.';
const outPath = process.argv[3] || path.join('data', 'flow-structure.json');

const norm = (p) => p.replace(/\\/g, '/');
function appRelDir(file) {
  let p = norm(file).replace(/^src\//, '').replace(/^app\//, '');
  return path.dirname(p);
}
function domainOf(dir) {
  const raw = dir.split('/').filter(Boolean);
  for (const s of raw) if (s.startsWith('(') && s.endsWith(')')) return s.slice(1, -1);
  const segs = raw.filter((s) => !s.startsWith('@') && s !== 'api' && !/^\[.*\]$/.test(s));
  return segs[0] || 'app';
}
function routeId(urlPath) {
  const segs = String(urlPath).replace(/^\//, '').split('/').filter(Boolean)
    .map((s) => s
      .replace(/^\[\[\.\.\.(\w+)\]\]$/, '$1')  // [[...slug]] optional catch-all
      .replace(/^\[\.\.\.(\w+)\]$/, '$1')       // [...slug] catch-all
      .replace(/^\[(\w+)\]$/, '$1'));           // [id] dynamic
  return segs.length ? segs.join('_') : 'home';
}
// screen id は extract-routes と同一規則（@slot を含めて一意化）にする（merge で id が一致する必要）
function screenId(urlPath, dir) {
  const slots = dir.split('/').filter((s) => s.startsWith('@')).map((s) => s.slice(1));
  const base = routeId(urlPath);
  return slots.length ? base + '_' + slots.join('_') : base;
}
const humanize = (s) => s.replace(/[-_/]+/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()).trim() || 'Home';
// path 文字列（/posts/123）→ route id（リンク先 = URL ベース。@slot は href で辿れないので base に解決）
const pathToId = (p) => routeId(String(p).split('?')[0].split('#')[0]);

// 画面ノード（page.tsx）と、appRelDir → screenId の対応
const screens = [];
const screenByDir = {};
for (const s of en.enumerateScreens(root)) {
  const dir = appRelDir(s.file), id = screenId(s.urlPath, dir);
  screenByDir[dir] = id;
  const dom = domainOf(dir);
  // module は flow view のグルーピングキー（template が要求）。硬層は domain を構造的 proxy として与える。
  // 軟層が public|my-page|manage|auth 等の意味的 module に refine してよい。
  screens.push({ id, title: humanize(id.replace(/_/g, ' ')), path: s.urlPath, component: norm(s.file), kind: '', domain: dom, module: dom });
}
// あるファイル dir から最近接の祖先 screen を見つける
function fromScreenOf(dir) {
  let d = dir;
  while (true) {
    if (screenByDir[d]) return screenByDir[d];
    const i = d.lastIndexOf('/');
    if (i < 0) break;
    d = d.slice(0, i);
  }
  return screenByDir[d] || null;
}

// 遷移パターン
const PATTERNS = [
  { re: /<Link\b[^>]*?href\s*=\s*(?:\{?\s*)["'`]([^"'`]+)["'`]/g, trigger: 'link' },
  { re: /(?:router|useRouter\(\)|navigate)\s*\.\s*(?:push|replace)\s*\(\s*["'`]([^"'`]+)["'`]/g, trigger: 'push' },
  { re: /(?:permanentRedirect|redirect)\s*\(\s*["'`]([^"'`]+)["'`]/g, trigger: 'redirect' },
];

const edges = [];
const edgeSeen = new Set();
const uncertainties = [];
const appDir = resolveAppDir(root);
if (appDir) {
  for (const file of walk(appDir, (_f, n) => /\.(tsx|jsx|ts|js)$/.test(n))) {
    const relFile = norm(path.relative(root, file)); // enumerator の .file と同じ root-relative に揃える
    const code = stripComments(read(file));
    const from = fromScreenOf(appRelDir(relFile));
    if (!from) continue;
    for (const { re, trigger } of PATTERNS) {
      re.lastIndex = 0;
      let m;
      while ((m = re.exec(code))) {
        const href = m[1];
        // テンプレートリテラル補間（`/x/${id}`）は静的に解決不能 → edge を出さず uncertainty に残す（#8）。
        if (href.includes('${') || href.includes('`')) continue;
        if (!href.startsWith('/')) continue; // 内部 path のみ（外部 URL/アンカーは無視）
        const to = pathToId(href);
        if (to === from) continue;
        const key = from + '>' + to + '>' + trigger;
        if (edgeSeen.has(key)) continue;
        edgeSeen.add(key);
        edges.push({ from, to, trigger, condition: '' });
      }
    }
    // テンプレートリテラル補間 href（動的遷移）は SOFT 残差として記録
    if (/href\s*=\s*\{?\s*`[^`]*\$\{/.test(code) || /(?:push|replace|redirect)\s*\(\s*`[^`]*\$\{/.test(code)) {
      uncertainties.push('動的遷移（テンプレートリテラル href）あり → 軟層で確認: ' + norm(path.relative(root, file)));
    }
  }
}

const model = { screens, edges, uncertainties };
fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, JSON.stringify(model, null, 1));

console.log('flow screens:', screens.length, '| edges:', edges.length,
  edges.length ? '| ' + edges.map((e) => e.from + '→' + e.to).join(', ') : '', '| dyn:', uncertainties.length);
console.log('-> ' + outPath);
