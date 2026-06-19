#!/usr/bin/env node
/* 硬層 adapter の自己検証（co-validation）。
 * scaffold golden slice（conforming fixture）に全 adapter を実走 → 期待値 assert → 正準 enumerator と突合 →
 * 生成データで merge+build+verify を通し、地図が決定的に PASS することを保証する。
 *   = scaffold（生成器）と adapter（検知器）と verify（描画器）が同じ conforming fixture を共有 → drift 不能。
 * 使い方: node verify-adapters.js
 */
const fs = require('fs'), path = require('path'), os = require('os');
const { execFileSync } = require('child_process');

const ADAPTERS = __dirname;
const ASSETS = path.join(__dirname, '..');
const TPL = path.join(__dirname, '../../../../scaffold/template'); // pack 直下の golden slice
const enumr = require('../../../../fitness-functions/lib/route-enumerator');

const cases = [];
const ok = (name, cond, detail) => cases.push({ name, ok: !!cond, detail: cond ? '' : (detail || '') });
const run = (cmd, args) => execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
const readJ = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'smap-verify-'));
const D = path.join(tmp, 'data');
fs.mkdirSync(D, { recursive: true });

// --- adapter 実走 -----------------------------------------------------------------------------
run('node', [path.join(ADAPTERS, 'extract-schema.nextjs.js'), TPL, path.join(D, 'db-schema.json')]);
run('node', [path.join(ADAPTERS, 'extract-indexes.nextjs.js'), path.join(TPL, 'prisma/schema.prisma'), path.join(D, 'db-indexes.json')]);
run('node', [path.join(ADAPTERS, 'extract-routes.nextjs.js'), TPL, D]);
run('node', [path.join(ADAPTERS, 'extract-authz.nextjs.js'), TPL, path.join(D, 'permissions.json')]);
run('node', [path.join(ADAPTERS, 'extract-links.nextjs.js'), TPL, path.join(D, 'flow-structure.json')]);

// --- 正準 enumerator（凍結カウント）----------------------------------------------------------
const canon = enumr.canonicalCounts(TPL);

// --- db-schema ------------------------------------------------------------------------------
const db = readJ(path.join(D, 'db-schema.json'));
ok('db-schema: tables=4', db.tables.length === 4, `tables=${db.tables.length}`);
ok('db-schema: relations=3', db.relations.length === 3, `relations=${db.relations.length}`);
const post = db.tables.find((t) => t.name === 'Post');
ok('db-schema: Post.companyId fk=Company', post && post.columns.some((c) => c.name === 'companyId' && c.fk === 'Company'));
ok('db-schema: Post.accessedFrom 1:N (lib/posts+lib/digest)', post && post.accessedFrom.includes('lib/posts') && post.accessedFrom.includes('lib/digest'), JSON.stringify(post && post.accessedFrom));

// --- routes / mutation surface --------------------------------------------------------------
const doms = ['cron', 'posts', 'webhooks'].map((id) => { const p = path.join(D, id + '.json'); return fs.existsSync(p) ? readJ(p) : null; });
ok('routes: domains posts/webhooks/cron 出力', doms.every(Boolean), 'missing domain file');
const allScreens = doms.filter(Boolean).reduce((n, d) => n + d.screens.length, 0);
const allApis = doms.filter(Boolean).reduce((n, d) => n + d.apis.length, 0);
ok('routes: screens=1 (canonical 一致)', allScreens === 1 && allScreens === canon.screens, `screens=${allScreens} canon=${canon.screens}`);
ok('routes: apis=6 (route entries 4 + actions 2 = canonical 一致)', allApis === 6 && allApis === canon.routeEntries + canon.serverActions, `apis=${allApis} canon=${canon.routeEntries + canon.serverActions}`);

const postsD = doms.find((d) => d && d.id === 'posts');
const webhooksD = doms.find((d) => d && d.id === 'webhooks');
const cronD = doms.find((d) => d && d.id === 'cron');
const findApi = (d, pred) => (d ? d.apis.find(pred) : null);

const postPost = findApi(postsD, (a) => a.method === 'POST' && a.path === '/api/posts');
ok('S4 kind: POST /api/posts = route-handler', postPost && postPost.kind === 'route-handler');
ok('dbTables: POST /api/posts writes Post (DAL コールグラフ)', postPost && postPost.dbTablesWrite.includes('Post'), JSON.stringify(postPost && postPost.dbTablesWrite));
ok('validation: POST /api/posts = body-schema', postPost && postPost.validation === 'body-schema', postPost && postPost.validation);

const actions = postsD ? postsD.apis.filter((a) => a.kind === 'server-action') : [];
ok('S4 kind: server-action 2 (createPostAction/deletePostAction)', actions.length === 2 && actions.length === canon.serverActions, `actions=${actions.length}`);
ok('calledByScreens: createPostAction ← posts', actions.some((a) => a.operationId === 'createPostAction' && a.calledByScreens.includes('posts')));

const wh = findApi(webhooksD, (a) => a.kind === 'webhook');
ok('S4 kind/trigger: webhook billing', wh && wh.trigger === 'webhook' && wh.path.includes('webhooks/billing'));
ok('validation: webhook = signature', wh && wh.validation === 'signature', wh && wh.validation);
ok('dbTables: webhook read+write WebhookEvent (tx 経由 write 捕捉)', wh && wh.dbTablesRead.includes('WebhookEvent') && wh.dbTablesWrite.includes('WebhookEvent'), JSON.stringify(wh && [wh.dbTablesRead, wh.dbTablesWrite]));

const cron = findApi(cronD, (a) => a.kind === 'cron');
ok('S4 kind/trigger: cron digest', cron && cron.trigger === 'cron');
ok('validation: cron = auth-gate', cron && cron.validation === 'auth-gate', cron && cron.validation);
ok('dbTables: cron reads Post', cron && cron.dbTablesRead.includes('Post'));

// --- authz ----------------------------------------------------------------------------------
const perms = readJ(path.join(D, 'permissions.json'));
ok('authz: roles MEMBER+ADMIN (Prisma enum)', perms.roles.map((r) => r.code).sort().join(',') === 'ADMIN,MEMBER', JSON.stringify(perms.roles.map((r) => r.code)));
const groups = perms.endpointAuth.map((e) => e.authGroup);
ok('authz: authenticated group', groups.includes('authenticated'));
ok('authz: out-of-band realms (cron-secret + webhook-signature)', groups.includes('cron-secret') && groups.includes('webhook-signature'), JSON.stringify(groups));
ok('authz: spaGuard /posts → /login', perms.spaGuards.some((g) => g.routePath === '/posts' && g.redirectTo === '/login'));

// --- flow -----------------------------------------------------------------------------------
const flow = readJ(path.join(D, 'flow-structure.json'));
ok('flow: edge posts→login (redirect)', flow.edges.some((e) => e.from === 'posts' && e.to === 'login'));
ok('flow: screen module 付与 (template グルーピング可)', flow.screens.every((s) => s.module));

// --- end-to-end: merge + build + verify -----------------------------------------------------
let e2e = 'OK';
try {
  run('node', [path.join(ASSETS, 'merge.js'), D, path.join(tmp, 'combined.json')]);
  run('node', [path.join(ASSETS, 'build.js'), path.join(ASSETS, 'template.html'), path.join(tmp, 'combined.json'), path.join(tmp, 'system-map.html')]);
  run('node', [path.join(ASSETS, 'verify.js'), path.join(tmp, 'system-map.html')]); // 非 0 終了で throw
} catch (e) {
  e2e = (e.stdout || '') + (e.stderr || e.message);
}
ok('end-to-end: merge+build+verify PASS（決定的に地図が描ける）', e2e === 'OK', String(e2e).slice(-400));

// --- 回帰: 敵対検証で見つかった must-fix の再発防止（最小 fixture を実走）----------------------
function mkFixture(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'smap-reg-'));
  for (const [rel, content] of Object.entries(files)) {
    const p = path.join(dir, rel);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, content);
  }
  return dir;
}
function routesOf(dir) {
  const out = path.join(dir, '_out'); fs.mkdirSync(out, { recursive: true });
  run('node', [path.join(ADAPTERS, 'extract-routes.nextjs.js'), dir, out]);
  const r = {}; for (const f of fs.readdirSync(out)) r[f.replace('.json', '')] = readJ(path.join(out, f));
  return r;
}
const api = (dom, pred) => (dom ? dom.apis.find(pred) : null);

// 回帰1: リテラル内の `}` と `prisma.x.op(` が本体を打ち切らない / phantom table を生まない（#2）
{
  const d = mkFixture({
    'app/api/alpha/route.ts': `import { prisma } from '@/lib/prisma';\nexport async function GET(){ const t = "}"; const x = await prisma.alpha.findMany(); return Response.json(x); }\nexport async function POST(){ const log = "calling prisma.delta.create( now }"; const w = await prisma.beta.create({ data: {} }); return Response.json(w); }\n`,
  });
  const r = routesOf(d);
  const g = api(r.alpha, (a) => a.method === 'GET'); const p = api(r.alpha, (a) => a.method === 'POST');
  ok('回帰#2: 文字列内 } で本体打切らない (GET reads Alpha)', g && g.dbTablesRead.includes('Alpha'), JSON.stringify(g && g.dbTablesRead));
  ok('回帰#2: 文字列内 prisma.x.op( が phantom にならない (POST writes Beta のみ)', p && p.dbTablesWrite.length === 1 && p.dbTablesWrite[0] === 'Beta', JSON.stringify(p && p.dbTablesWrite));
  fs.rmSync(d, { recursive: true, force: true });
}
// 回帰2: メンバアクセス `.filter(` を DAL fn `filter` と誤認しない（#3）
{
  const d = mkFixture({
    'lib/dal.ts': `import { prisma } from '@/lib/prisma';\nexport async function filter(id){ return prisma.secret.deleteMany({ where: { id } }); }\n`,
    'app/api/y/route.ts': `export async function GET(){ const evens = [1,2,3].filter((n)=>n%2===0); return Response.json(evens); }\n`,
  });
  const r = routesOf(d);
  const g = api(r.y, (a) => a.method === 'GET');
  ok('回帰#3: items.filter() を DAL fn filter と誤認しない (no phantom Secret)', g && g.dbTablesWrite.length === 0 && g.dbTablesRead.length === 0, JSON.stringify(g && [g.dbTablesRead, g.dbTablesWrite]));
  fs.rmSync(d, { recursive: true, force: true });
}
// 回帰3: @slot parallel route が screen id 衝突しない（#1）
{
  const d = mkFixture({
    'app/dashboard/page.tsx': `export default function P(){ return null; }\n`,
    'app/dashboard/@analytics/page.tsx': `export default function A(){ return null; }\n`,
  });
  const r = routesOf(d);
  const ids = Object.values(r).flatMap((dm) => dm.screens.map((s) => s.id));
  ok('回帰#1: @slot page が screen id 衝突しない', ids.length === 2 && new Set(ids).size === 2, JSON.stringify(ids));
  fs.rmSync(d, { recursive: true, force: true });
}
// 回帰4: テンプレートリテラル href が garbage edge を生まない（#8）
{
  const d = mkFixture({
    'app/x/page.tsx': `import Link from 'next/link';\nexport default function X(){ const id='1'; return (<div><Link href={\`/detail/\${id}\`}>d</Link><Link href="/static">s</Link></div>); }\n`,
  });
  const out = path.join(d, 'flow.json');
  run('node', [path.join(ADAPTERS, 'extract-links.nextjs.js'), d, out]);
  const fl = readJ(out);
  ok('回帰#8: 動的 href は edge を出さず uncertainty に（garbage なし）', !fl.edges.some((e) => /[$`]/.test(e.to)) && fl.edges.some((e) => e.to === 'static') && fl.uncertainties.length > 0, JSON.stringify(fl.edges.map((e) => e.to)));
  fs.rmSync(d, { recursive: true, force: true });
}
// 回帰5: @relation の multiline + references-before-fields でも relation+fk が出る（#9/#10）
{
  const d = mkFixture({
    'prisma/schema.prisma': `model User { id String @id\n  teams Team[] }\nmodel Team {\n  id String @id\n  owner User @relation("O", references: [id], fields: [ownerId])\n  ownerId String\n  lead User @relation(\n    "L",\n    fields: [leadId],\n    references: [id]\n  )\n  leadId String\n}\n`,
  });
  const out = path.join(d, 'db.json');
  run('node', [path.join(ADAPTERS, 'extract-schema.nextjs.js'), d, out]);
  const db2 = readJ(out);
  const team = db2.tables.find((t) => t.name === 'Team');
  const ownerFk = team.columns.find((c) => c.name === 'ownerId');
  const leadFk = team.columns.find((c) => c.name === 'leadId');
  ok('回帰#10: references-before-fields の fk 解決 (ownerId→User)', ownerFk && ownerFk.fk === 'User', JSON.stringify(ownerFk));
  ok('回帰#9: multiline @relation の fk 解決 (leadId→User)', leadFk && leadFk.fk === 'User', JSON.stringify(leadFk));
  fs.rmSync(d, { recursive: true, force: true });
}

// --- 結果 -----------------------------------------------------------------------------------
let pass = 0, fail = 0;
for (const c of cases) { console.log((c.ok ? '  o ' : '  x ') + c.name + (c.ok ? '' : '  <- ' + c.detail)); c.ok ? pass++ : fail++; }
try { fs.rmSync(tmp, { recursive: true, force: true }); } catch {}
console.log(`\n${fail ? 'FAIL' : 'PASS'} (${pass}/${cases.length})`);
process.exit(fail ? 1 : 0);
