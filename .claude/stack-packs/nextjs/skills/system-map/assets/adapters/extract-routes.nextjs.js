#!/usr/bin/env node
/* App Router の page.tsx・api の route.ts・actions.ts から「画面・API（mutation 面）」の骨格を決定的抽出 (無LLM)
 * → ドメインごとの `<domain>.json`（schema.md の `<domain>.json` 契約）。
 *
 * ★ 正準カウントは単一定義（DRY）: route / screen / server-action / cron / mutation の母集合は
 *   `../../../../fitness-functions/lib/route-enumerator.js` を import する（数え方を再実装しない）。
 *   fitness-functions と system-map が同じカウントを見ることで「地図」と「検知層」が一致する。
 *
 * 硬層が決める: 何が在るか（screen/api の identity）/ api.kind（route-handler|server-action|webhook|cron ★S4）/
 *   trigger（page|webhook|cron|internal）/ validation の分類 / dbTablesRead|Write（DAL コールグラフ）/ calledByScreens。
 * 軟層が足す（空で出す）: 画面 kind の意味（list|form|…）/ purpose / summary / gotchas / idempotency 判定。
 *
 * 使い方: node extract-routes.nextjs.js [root=.] [outDir=data]
 *   → outDir に `<domain>.json` を複数出力。軟層は同名ファイルを上書きで enrich する（merge.js は各 1 回読む）。 */
const fs = require('fs'), path = require('path');
const enamong = require('../../../../fitness-functions/lib/route-enumerator');
const { walk, read, stripComments, blankLiterals } = require('../../../../fitness-functions/lib/fs-util');

const root = process.argv[2] || '.';
const outDir = process.argv[3] || 'data';

const READ_OPS = new Set(['findMany', 'findFirst', 'findUnique', 'findUniqueOrThrow', 'findFirstOrThrow', 'count', 'aggregate', 'groupBy']);
const WRITE_OPS = new Set(['create', 'createMany', 'createManyAndReturn', 'update', 'updateMany', 'upsert', 'delete', 'deleteMany']);
// client.model.op( を捕捉。prisma / transaction client (tx) / 別名 db 等を許容（model の write が tx 経由でも拾う）。
const PRISMA_OP_RE = /\b(?:prisma|tx|trx|db|client)\.([a-z]\w*)\.(\w+)\s*\(/g;
const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);

/** 関数本体を取り出す（パラメータ括弧内の `{`・generics `<{…}>` を本体開始と誤認しない）。 */
function bodyAfter(code, fromIdx) {
  let i = fromIdx, pd = 0, ad = 0, started = false;
  for (; i < code.length; i++) {
    const c = code[i];
    if (c === '(') { pd++; started = true; }
    else if (c === ')') pd--;
    else if (c === '<') ad++;
    else if (c === '>') { if (ad > 0) ad--; }
    else if (c === '{' && pd === 0 && ad === 0 && started) break;
  }
  if (i >= code.length) return '';
  let depth = 0;
  for (let j = i; j < code.length; j++) {
    if (code[j] === '{') depth++;
    else if (code[j] === '}') { if (--depth === 0) return code.slice(i + 1, j); }
  }
  return code.slice(i + 1);
}

/** ファイル内の各 export 関数 → 本体（コメント除去済）。 */
function exportedFnBodies(code) {
  const out = {};
  const marks = [];
  for (const m of code.matchAll(/export\s+(?:async\s+)?function\s+([a-zA-Z0-9_$]+)/g)) marks.push({ name: m[1], idx: m.index });
  for (const m of code.matchAll(/export\s+const\s+([a-zA-Z0-9_$]+)\s*(?::[^=]+)?=\s*(?:async\b|\(|function\b)/g)) marks.push({ name: m[1], idx: m.index });
  for (const m of marks) out[m.name] = bodyAfter(code, m.idx);
  return out;
}

function opsOf(body) {
  const reads = new Set(), writes = new Set();
  for (const m of body.matchAll(PRISMA_OP_RE)) {
    const model = cap(m[1]);
    if (READ_OPS.has(m[2])) reads.add(model);
    else if (WRITE_OPS.has(m[2])) writes.add(model);
  }
  return { reads, writes };
}

// --- DAL コールグラフ: lib/ の export 関数 → 触る model（read/write）---------------------------
// blankLiterals: 文字列/テンプレ/正規表現の内部を空白化（`"prisma.x.create("` 等の phantom op を防ぐ）。
const scan = (code) => blankLiterals(stripComments(code));
const dalMap = {}; // fnName -> { reads:[], writes:[] }
for (const d of ['lib', 'src/lib'].map((x) => path.join(root, x)).filter(fs.existsSync)) {
  for (const f of walk(d, (_x, n) => /\.(ts|tsx)$/.test(n))) {
    const bodies = exportedFnBodies(scan(read(f)));
    for (const [name, body] of Object.entries(bodies)) {
      const { reads, writes } = opsOf(body);
      dalMap[name] = { reads: [...reads], writes: [...writes] };
    }
  }
}
const dalNames = Object.keys(dalMap);

/** api 本体から dbTablesRead/Write を解決（本体内の直 prisma + 呼んでいる DAL 関数の合算）。 */
function resolveDbTables(body) {
  const { reads, writes } = opsOf(body); // S2 違反の直叩きも拾う
  for (const name of dalNames) {
    // (?<![.\w]): メンバアクセス `.name(` や `xname(` を除外（`items.filter(` を DAL fn `filter` と誤認しない）
    if (new RegExp('(?<![.\\w])' + name + '\\s*\\(').test(body)) {
      dalMap[name].reads.forEach((r) => reads.add(r));
      dalMap[name].writes.forEach((w) => writes.add(w));
    }
  }
  return { read: [...reads].sort(), write: [...writes].sort() };
}

// validation 分類。body はリテラル空白化済（文字列内の "verifySignature()" 等で誤検知しない）。
function detectValidation(body, importsValidations, kind) {
  const hasSchema = /safeParse|\.parse\s*\(/.test(body) && importsValidations;
  const hasSig = /verifySignature\s*\(|verifyWebhook\s*\(|\.constructEvent\s*\(|\bsvix\b/.test(body);
  if (kind === 'webhook' && hasSig) return 'signature';      // webhook は署名が load-bearing
  if (hasSchema) return 'body-schema';                       // 確定 body-schema を outbound secret/sig で潰さない（#6）
  if (hasSig) return 'signature';
  if (/\bCRON_SECRET\b/.test(body)) return 'auth-gate';      // cron secret に限定（generic *_SECRET は outbound 誤検知）
  if (/formData\s*\(\)|multipart|\.blob\s*\(\)|\bnew\s+File\b/.test(body)) return 'file';
  return 'none';
}

// --- app-relative dir / domain / screen-id ヘルパ ----------------------------------------------
const norm = (p) => p.replace(/\\/g, '/');
function appRelDir(file) {
  let p = norm(file).replace(/^src\//, '').replace(/^app\//, '');
  return path.dirname(p); // 'posts' / 'api/webhooks/billing' / 'posts'（actions.ts）
}
function domainOf(dir) {
  const raw = dir.split('/').filter(Boolean);
  for (const s of raw) if (s.startsWith('(') && s.endsWith(')')) return s.slice(1, -1); // route group が domain
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
// screen id は page.tsx ごとに一意。parallel route slot `@x` は同 urlPath に collapse するため
// slot 名を付与して衝突を防ぐ（host page と slot page は別ノード・#1）。route group は collapse しても
// URL 一意なので suffix しない（host page は clean な url ベース id を保つ）。
function screenId(urlPath, dir) {
  const slots = dir.split('/').filter((s) => s.startsWith('@')).map((s) => s.slice(1));
  const base = routeId(urlPath);
  return slots.length ? base + '_' + slots.join('_') : base;
}
const humanize = (s) => s.replace(/[-_/]+/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()).trim() || 'Home';

// --- 列挙（正準 enumerator）-------------------------------------------------------------------
const screens = enamong.enumerateScreens(root);
const routes = enamong.enumerateRoutes(root);
const actions = enamong.enumerateServerActions(root);
const cronPaths = new Set(enamong.enumerateCrons(root).map((c) => c.path));

// domain バケツ
const domains = {}; // id -> {id,name,purpose,screens,apis,gotchas,uncertainties}
const bucket = (id) => (domains[id] = domains[id] || { id, name: humanize(id), purpose: '', screens: [], apis: [], gotchas: [], uncertainties: [] });

// ファイルキャッシュ: codeOf=コメント除去（文字列保持・import/marker 用）/ scanOf=さらにリテラル空白化（本体解析用）
const codeCache = {}, scanCache = {};
const codeOf = (file) => (codeCache[file] = codeCache[file] || stripComments(read(path.join(root, file))));
const scanOf = (file) => (scanCache[file] = scanCache[file] || blankLiterals(codeOf(file)));
const importsValidations = (file) => /from\s+['"][^'"]*lib\/validations/.test(codeOf(file));
/** route handler の指定 method の本体を取る（function/const 両形・HOC ラップ等で失敗時は全体フォールバック）。 */
function methodBody(sc, method) {
  let idx = sc.search(new RegExp('export\\s+(?:async\\s+)?function\\s+' + method + '\\b'));
  if (idx < 0) idx = sc.search(new RegExp('export\\s+const\\s+' + method + '\\b'));
  if (idx < 0) return sc;
  return bodyAfter(sc, idx) || sc;
}

// screens: page.tsx（id は @slot を含めて一意化）
const screenByDir = {}; // appRelDir -> screenId
for (const s of screens) {
  const dir = appRelDir(s.file), id = screenId(s.urlPath, dir);
  screenByDir[dir] = id;
  bucket(domainOf(dir)).screens.push({
    id, title: humanize(id.replace(/_/g, ' ')), route: s.urlPath, module: '', kind: '',
    permission: '', userTypes: [], actions: [],
  });
}

// route handlers: route.ts × method
for (const r of routes) {
  const dir = appRelDir(r.file);
  const id = domainOf(dir);
  const isCron = cronPaths.has(r.urlPath);
  const kind = isCron ? 'cron' : r.isWebhook ? 'webhook' : 'route-handler';
  const trigger = isCron ? 'cron' : r.isWebhook ? 'webhook' : 'page';
  const body = methodBody(scanOf(r.file), r.method);
  const importsVal = importsValidations(r.file);
  const db = resolveDbTables(body);
  const idem = (kind === 'webhook' || kind === 'cron') ? '' : 'n/a';
  const d = bucket(id);
  d.apis.push({
    method: r.method, path: r.urlPath, operationId: r.method + '_' + (r.segments.join('_') || 'root'),
    kind, trigger, summary: '', permission: '', dbTablesRead: db.read, dbTablesWrite: db.write,
    calledByScreens: [], validation: detectValidation(body, importsVal, kind), idempotency: idem, gotchas: [],
  });
  if (idem === '') d.uncertainties.push('idempotency 要判定（webhook/cron）: ' + r.method + ' ' + r.urlPath);
  if (r.isMutating && db.write.length === 0) d.uncertainties.push('dbTablesWrite 未解決（DAL 越えか直 prisma 無し）: ' + r.method + ' ' + r.urlPath);
}

// server actions: actions.ts module-level export
for (const a of actions) {
  const dir = appRelDir(a.file);
  const id = domainOf(dir);
  const bodies = exportedFnBodies(scanOf(a.file));
  const body = bodies[a.exportName] || '';
  const importsVal = importsValidations(a.file);
  const db = resolveDbTables(body);
  const calledBy = screenByDir[dir] ? [screenByDir[dir]] : [];
  bucket(id).apis.push({
    method: 'ACTION', path: a.exportName, operationId: a.exportName,
    kind: 'server-action', trigger: 'internal', summary: '', permission: '',
    dbTablesRead: db.read, dbTablesWrite: db.write, calledByScreens: calledBy,
    validation: detectValidation(body, importsVal, 'server-action'), idempotency: 'n/a', gotchas: [],
  });
}

// 出力
fs.mkdirSync(outDir, { recursive: true });
const ids = Object.keys(domains).sort();
for (const id of ids) {
  fs.writeFileSync(path.join(outDir, id + '.json'), JSON.stringify(domains[id], null, 1));
}
const nScreens = ids.reduce((n, i) => n + domains[i].screens.length, 0);
const nApis = ids.reduce((n, i) => n + domains[i].apis.length, 0);

// 正準カウント突合（fitness と母集合一致を自己ガード・id 衝突も検出）
const cc = enamong.canonicalCounts(root);
const distinctIds = new Set(ids.flatMap((i) => domains[i].screens.map((s) => s.id))).size;
const routeApis = ids.reduce((n, i) => n + domains[i].apis.filter((a) => a.kind !== 'server-action').length, 0);
const actionApis = ids.reduce((n, i) => n + domains[i].apis.filter((a) => a.kind === 'server-action').length, 0);
const warns = [];
if (nScreens !== cc.screens) warns.push(`screens ${nScreens} != canonical ${cc.screens}`);
if (distinctIds !== nScreens) warns.push(`screen id 衝突: distinct ${distinctIds} != ${nScreens}`);
if (routeApis !== cc.routeEntries) warns.push(`route apis ${routeApis} != canonical ${cc.routeEntries}`);
if (actionApis !== cc.serverActions) warns.push(`action apis ${actionApis} != canonical ${cc.serverActions}`);
if (warns.length) { console.error('⚠️ 正準カウント不一致（地図が enumerator と乖離）:'); warns.forEach((w) => console.error('  - ' + w)); }

console.log('domains:', ids.length, '|', ids.join(', '));
console.log('screens:', nScreens, '| apis:', nApis, '| DAL fns:', dalNames.length, warns.length ? '| ⚠️ count drift' : '| ✓ canonical');
console.log('-> ' + outDir + '/{' + ids.join(',') + '}.json');
