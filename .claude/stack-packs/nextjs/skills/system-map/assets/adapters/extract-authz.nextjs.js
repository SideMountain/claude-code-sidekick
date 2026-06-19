#!/usr/bin/env node
/* 認可の骨格を決定的抽出 (無LLM) → permissions.json（schema.md の permissions.json 契約）。
 *
 * [Next] 認可は二層（ARCHITECTURE.md S5/S6）。本 adapter は**入口ゲート**を硬く拾う:
 *   - roles            : Prisma enum（model の `role <Enum>` 型）から
 *   - middleware.ts    : matcher 式（在れば）= 粗いゲート
 *   - requireRole([..]): role allowlist のゲート
 *   - requireSession() : 認証必須ゲート（authGroup=authenticated）
 *   - out-of-band realm: webhook 署名 / cron secret（page から辿れない入口の認証境界・S5 残余）
 *   - spaGuards        : page の `redirect('/login')` 等（未認証リダイレクト）
 * object-level 認可（所有・テナント検証 = DAL 側 S6）は意味付けが要るので軟層に委ねる（uncertainties に残す）。
 *
 * 使い方: node extract-authz.nextjs.js [root=.] [out=data/permissions.json] [schema=<root>/prisma/schema.prisma] */
const fs = require('fs'), path = require('path');
const en = require('../../../../fitness-functions/lib/route-enumerator');
const { read, stripComments, blankLiterals } = require('../../../../fitness-functions/lib/fs-util');

const root = process.argv[2] || '.';
const outPath = process.argv[3] || path.join('data', 'permissions.json');
const schemaPath = process.argv[4] || path.join(root, 'prisma', 'schema.prisma');

// --- roles: Prisma enum --------------------------------------------------------------------
function parseRoles() {
  if (!fs.existsSync(schemaPath)) return [];
  const clean = read(schemaPath).replace(/\/\/[^\n]*/g, '');
  const enums = {};
  for (const m of clean.matchAll(/enum\s+(\w+)\s*\{([\s\S]*?)\}/g)) {
    enums[m[1]] = m[2].split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('@') && /^\w+$/.test(l));
  }
  // model の `role <Enum>` 型を優先。無ければ名前に role を含む enum。
  const fm = clean.match(/\brole\s+([A-Z]\w*)\b/);
  let name = fm && enums[fm[1]] ? fm[1] : Object.keys(enums).find((e) => /role/i.test(e));
  return (name ? enums[name] : []).map((v) => ({ code: v, name: v, scope: '', description: '' }));
}

// --- ゲート検出ヘルパ ----------------------------------------------------------------------
// requireRole の allowlist を読む。code は文字列保持版（'ADMIN' リテラル role を読むため）。
// spread/変数/計算値の token は role として採用せず dynamic フラグを立てる（#7: '...base' を role と誤認しない）。
function rolesInRequireRole(code) {
  const out = new Set();
  let dynamic = false;
  for (const m of code.matchAll(/requireRole\s*\(([^)]*)\)/g)) {
    const arr = m[1].match(/\[([^\]]*)\]/);
    if (!arr) { dynamic = true; continue; }            // requireRole(VAR) インライン配列でない
    for (const t of arr[1].split(',')) {
      const r = t.trim().replace(/^Role\./, '').replace(/['"]/g, '');
      if (!r) continue;
      if (/^[A-Z][A-Z0-9_]*$/.test(r)) out.add(r);     // 有効な role 識別子のみ
      else dynamic = true;                             // ...spread / 小文字変数 / 計算値
    }
  }
  return { roles: [...out].sort(), dynamic };
}
function gateOf(code) {
  // code は文字列保持（role リテラル用）。signature/secret 判定は blanked で行う（文字列内の言及で誤検知しない・#4）。
  const blanked = blankLiterals(code);
  // 優先度: role allowlist > role(dynamic) > signature > cron-secret > authenticated > none
  const { roles, dynamic } = rolesInRequireRole(code);
  if (roles.length) return { group: 'role:' + roles.join('+'), source: 'DAL requireRole([' + roles.join(', ') + '])', dynamic };
  if (dynamic) return { group: 'role:dynamic', source: 'DAL requireRole(<動的 allowlist>)', dynamic: true };
  if (/verifySignature\s*\(|verifyWebhook\s*\(|\.constructEvent\s*\(|\bsvix\b/.test(blanked)) return { group: 'webhook-signature', source: 'route 署名検証（out-of-band realm・S5残余）' };
  if (/\bCRON_SECRET\b/.test(blanked)) return { group: 'cron-secret', source: 'CRON_SECRET（out-of-band realm・S5残余）' }; // cron secret に限定（generic *_SECRET は outbound 鍵で誤検知・#5）
  if (/requireSession\s*\(/.test(blanked)) return { group: 'authenticated', source: 'DAL requireSession()' };
  return null;
}

const groups = {}; // authGroup -> { paths:Set, source }
const roleUncertain = new Set();
const addGate = (g, p) => {
  if (!g) return;
  (groups[g.group] = groups[g.group] || { paths: new Set(), source: g.source }).paths.add(p);
  if (g.dynamic) roleUncertain.add(p);
};

const codeOf = (rel) => stripComments(read(path.join(root, rel)));

// route handlers（file 単位でゲート判定 → urlPath を paths に）
for (const r of en.enumerateRoutes(root)) addGate(gateOf(codeOf(r.file)), r.urlPath);
// pages
const spaGuards = [];
for (const s of en.enumerateScreens(root)) {
  const code = codeOf(s.file);
  addGate(gateOf(code), s.urlPath);
  const rd = code.match(/redirect\(\s*['"`]([^'"`]+)['"`]\s*\)/); // redirect 先は文字列リテラルを読む（保持版 code）
  if (rd && /requireSession|auth\.ok|!\s*auth|!\s*session/.test(blankLiterals(code))) {
    spaGuards.push({ module: '', routePath: s.urlPath, requiredPermission: 'authenticated', userTypes: [], redirectTo: rd[1] });
  }
}
// server actions（path = 関数名）
for (const a of en.enumerateServerActions(root)) addGate(gateOf(codeOf(a.file)), a.exportName);

// middleware.ts matcher（在れば粗いゲートとして）
for (const mw of ['middleware.ts', 'src/middleware.ts', 'middleware.js', 'src/middleware.js']) {
  const p = path.join(root, mw);
  if (!fs.existsSync(p)) continue;
  const code = stripComments(read(p));
  const mm = code.match(/matcher\s*:\s*\[([^\]]*)\]/);
  const paths = mm ? mm[1].split(',').map((s) => s.trim().replace(/['"]/g, '')).filter(Boolean) : [];
  paths.forEach((pp) => addGate({ group: 'middleware', source: 'middleware.ts matcher' }, pp));
  break;
}

const endpointAuth = Object.keys(groups).sort().map((g) => ({
  authGroup: g, paths: [...groups[g].paths].sort(), permitAll: false, source: groups[g].source,
}));

const uncertainties = ['object-level 認可（所有/テナント検証 = DAL S6）は意味付け要 → 軟層で確認'];
if (roleUncertain.size) uncertainties.push('requireRole の allowlist が動的（spread/変数）→ 軟層で role 解決: ' + [...roleUncertain].sort().join(', '));

const model = {
  roles: parseRoles(),
  endpointAuth,
  spaGuards,
  notes: [],
  uncertainties,
};
fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, JSON.stringify(model, null, 1));

console.log('roles:', model.roles.map((r) => r.code).join(',') || '(none)',
  '| authGroups:', endpointAuth.length, '|', endpointAuth.map((e) => e.authGroup + '(' + e.paths.length + ')').join(' '),
  '| spaGuards:', spaGuards.length);
console.log('-> ' + outPath);
