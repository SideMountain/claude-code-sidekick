// route-enumerator.js — 正準 enumerator（ARCHITECTURE.md 決定性スコープの「正準カウント凍結」のコード実体）
//
// ★ 単一定義の原則（DRY / 正準カウント凍結）:
//   route 数は「数え方」で揺れる（ファイル数 / method export 数 / page+API 合算 = 87/88/92/93/112 と dogfood で測定がぶれた）。
//   このモジュールが **唯一の正準定義** であり、fitness-functions と（後続の）system-map route adapter は
//   必ずここを import する。母集合を二重定義しない。
//
//   正準定義（凍結）:
//     - route entry  = (route.ts ファイル, HTTP method export) の組  ……「1 method = 1 entry」
//     - screen       = page.tsx 1 つ                                  ……「1 page = 1 screen」
//     - server action= actions.ts の module-level named export 1 つ   ……「1 export = 1 action」
//     - cron         = vercel.json crons[] の 1 エントリ
//     - mutation 面  = (mutating route method) + (server action) + (cron) + (webhook route)
//                       を trigger taxonomy 付きで列挙（ARCHITECTURE.md S4）
//
// 依存ゼロ（Node 標準のみ）。正規表現ベースの静的走査（実行しない・型解決しない）。

const fs = require('fs');
const path = require('path');
const { walk, read, resolveAppDir, rel } = require('./fs-util');

const HTTP_METHODS = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'];
const MUTATING_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

// webhook と判定する route segment（provider-callback）。両表記を許容。
const WEBHOOK_SEGMENT = /(^|\/)(webhooks?|callbacks?)(\/|$)/i;

/** route.ts / route.js から named export された HTTP method を抽出。 */
function methodExports(src) {
  const found = new Set();
  // export async function GET(...) / export function POST(...)
  for (const m of src.matchAll(/export\s+(?:async\s+)?function\s+([A-Z]+)\b/g)) {
    if (HTTP_METHODS.includes(m[1])) found.add(m[1]);
  }
  // export const GET = ... / export const POST: ... =
  for (const m of src.matchAll(/export\s+const\s+([A-Z]+)\s*[:=]/g)) {
    if (HTTP_METHODS.includes(m[1])) found.add(m[1]);
  }
  // export { GET, POST } / export { handler as GET }（エクスポート名 = `as` の右側）
  for (const m of src.matchAll(/export\s*\{([^}]*)\}/g)) {
    for (const part of m[1].split(',')) {
      const seg = part.trim().split(/\s+as\s+/);
      const name = (seg[1] || seg[0] || '').trim(); // 別名があれば右側（公開名）
      if (HTTP_METHODS.includes(name)) found.add(name);
    }
  }
  return [...found];
}

/** app 配下の URL segment（route group `(x)` と private `_x` を除去）。 */
function urlSegments(appDir, file) {
  const r = rel(appDir, path.dirname(file));
  if (r === '' || r === '.') return [];
  return r.split('/').filter((s) => !(s.startsWith('(') && s.endsWith(')')) && !s.startsWith('@'));
}

/** route entry を列挙: (route.ts, method) = 1 entry。 */
function enumerateRoutes(root) {
  const appDir = resolveAppDir(root);
  if (!appDir) return [];
  const files = walk(appDir, (_f, name) => /^route\.(ts|js|tsx|jsx)$/.test(name));
  const out = [];
  for (const file of files) {
    const src = read(file);
    const segs = urlSegments(appDir, file);
    const isWebhook = WEBHOOK_SEGMENT.test(segs.join('/'));
    for (const method of methodExports(src)) {
      out.push({
        file: rel(root, file),
        method,
        segments: segs,
        urlPath: '/' + segs.join('/'),
        isWebhook,
        isMutating: MUTATING_METHODS.has(method),
      });
    }
  }
  return out.sort((a, b) => (a.file + a.method).localeCompare(b.file + b.method));
}

/** screen を列挙: page.tsx = 1 screen。 */
function enumerateScreens(root) {
  const appDir = resolveAppDir(root);
  if (!appDir) return [];
  const files = walk(appDir, (_f, name) => /^page\.(tsx|jsx|ts|js)$/.test(name));
  return files
    .map((file) => {
      const segs = urlSegments(appDir, file);
      return { file: rel(root, file), urlPath: '/' + segs.join('/'), segments: segs };
    })
    .sort((a, b) => a.file.localeCompare(b.file));
}

/** module-level `'use server'`（ファイル先頭）を持つか。 */
function isModuleLevelServerActionFile(src) {
  // 先頭のコメント/空行を飛ばして最初の実文が 'use server' か
  const stripped = src
    .replace(/^﻿/, '')
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l !== '' && !l.startsWith('//') && !l.startsWith('/*') && !l.startsWith('*'));
  return /^['"]use server['"];?$/.test(stripped[0] || '');
}

/**
 * server action を列挙: **actions.ts の module-level named export（関数値のみ）= 1 action**（凍結定義）。
 * 正準カウントの正確性のため、母集合は凍結定義に厳密一致させる:
 *   - `actions.ts` 以外 / module-level でない `'use server'`（= inline・misplaced）は action と数えない
 *     （それらは違反であって legit な mutation 面ではない。S4 check が error として捕まえる）
 *   - 関数でない export（`export const MAX = 10` / `export type` 等）は action でない
 */
function enumerateServerActions(root) {
  const dirs = ['app', 'src/app', 'lib', 'src/lib', 'components', 'src/components']
    .map((d) => path.join(root, d))
    .filter((d) => fs.existsSync(d));
  const seen = new Set();
  const out = [];
  for (const dir of dirs) {
    for (const file of walk(dir, (_f, name) => /\.(ts|tsx|js|jsx)$/.test(name))) {
      if (seen.has(file)) continue;
      seen.add(file);
      const src = read(file);
      if (!/['"]use server['"]/.test(src)) continue;
      const moduleLevel = isModuleLevelServerActionFile(src);
      const inActionsFile = path.basename(file) === 'actions.ts';
      if (!(moduleLevel && inActionsFile)) continue; // 凍結定義: actions.ts の module-level のみ
      for (const m of src.matchAll(/export\s+(?:async\s+)?function\s+([a-zA-Z0-9_$]+)/g)) {
        out.push({ file: rel(root, file), exportName: m[1], moduleLevel, inActionsFile });
      }
      // 関数値の const のみ（`= async` / `= (...) =>` / `= function`）。データ const は除外。
      for (const m of src.matchAll(/export\s+const\s+([a-zA-Z0-9_$]+)\s*(?::[^=]+)?=\s*(?:async\b|\(|function\b)/g)) {
        out.push({ file: rel(root, file), exportName: m[1], moduleLevel, inActionsFile });
      }
    }
  }
  return out.sort((a, b) => (a.file + a.exportName).localeCompare(b.file + b.exportName));
}

/** cron を列挙: vercel.json の crons[]。 */
function enumerateCrons(root) {
  const p = path.join(root, 'vercel.json');
  if (!fs.existsSync(p)) return [];
  try {
    const json = JSON.parse(read(p));
    const crons = Array.isArray(json.crons) ? json.crons : [];
    return crons.map((c) => ({ path: c.path, schedule: c.schedule }));
  } catch {
    return [];
  }
}

/**
 * mutation 面を trigger taxonomy 付きで統合列挙（ARCHITECTURE.md S4）。
 * trigger: 'page'（screen 到達）/ 'webhook'（provider-callback）/ 'cron'（scheduler）/ 'internal'（server action）
 */
function enumerateMutations(root) {
  const out = [];
  const cronPaths = new Set(enumerateCrons(root).map((c) => c.path));
  for (const r of enumerateRoutes(root)) {
    const isCron = cronPaths.has(r.urlPath);
    // mutating route + webhook（GET の検証ハンドシェイク含む）+ cron route を面に含める（S4: blast-radius を取りこぼさない）
    if (!r.isMutating && !r.isWebhook && !isCron) continue;
    out.push({
      kind: 'route-handler',
      ref: `${r.file}#${r.method}`,
      trigger: isCron ? 'cron' : r.isWebhook ? 'webhook' : 'page',
      urlPath: r.urlPath,
    });
  }
  for (const a of enumerateServerActions(root)) {
    out.push({ kind: 'server-action', ref: `${a.file}#${a.exportName}`, trigger: 'internal' });
  }
  // route handler を持たない cron（path だけ・別 handler 形態）も面に含める
  for (const c of enumerateCrons(root)) {
    if (!out.some((m) => m.urlPath === c.path)) {
      out.push({ kind: 'cron', ref: `${c.path} @ ${c.schedule}`, trigger: 'cron', urlPath: c.path });
    }
  }
  return out;
}

/** 正準カウント（fitness / system-map / レポートが参照する単一の母集合）。 */
function canonicalCounts(root) {
  const routes = enumerateRoutes(root);
  const screens = enumerateScreens(root);
  const actions = enumerateServerActions(root);
  const crons = enumerateCrons(root);
  const mutations = enumerateMutations(root);
  return {
    routeEntries: routes.length,      // (route.ts, method) 組
    routeFiles: new Set(routes.map((r) => r.file)).size,
    screens: screens.length,          // page.tsx
    serverActions: actions.length,    // actions.ts module-level export
    crons: crons.length,
    mutationSurface: mutations.length,
    webhooks: routes.filter((r) => r.isWebhook).length,
  };
}

module.exports = {
  HTTP_METHODS, MUTATING_METHODS,
  enumerateRoutes, enumerateScreens, enumerateServerActions, enumerateCrons,
  enumerateMutations, canonicalCounts,
  isModuleLevelServerActionFile, methodExports,
};
