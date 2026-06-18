// checks.js — ARCHITECTURE.md の各 MUST を grep-checkable assertion に落とした fitness 関数群。
//
// 各 check は ARCHITECTURE.md の「検証」行を**厳密に**写す（dogfood 教訓: spec をエージェント解釈で動かさない）。
// severity:
//   'error' = HARD（決定性 load-bearing / 違反は CI を落とす）
//   'warn'  = SHOULD / SOFT 残差（決定性スコープ表で「存在=HARD・網羅=SOFT」等。落とさず可視化のみ）
//
// 依存ゼロ（Node 標準のみ・regex 静的走査）。下流PJ はこのファイルを読めば各ルールの判定が分かる。

const fs = require('fs');
const path = require('path');
const { walk, read, resolveAppDir, resolveSourceDirs, isSource, rel, stripComments } = require('./lib/fs-util');
const enumr = require('./lib/route-enumerator');

// ---- 共通ヘルパー ---------------------------------------------------------

function lineOf(src, index) {
  return src.slice(0, index).split('\n').length;
}
function matchLines(src, regex) {
  const out = [];
  const re = new RegExp(regex.source, regex.flags.includes('g') ? regex.flags : regex.flags + 'g');
  let m;
  while ((m = re.exec(src))) out.push({ line: lineOf(src, m.index), text: m[0] });
  return out;
}
/** 指定行（1-based）の生テキスト。escape-hatch コメント判定用。 */
function rawLine(src, line) {
  return (src.split('\n')[line - 1] || '');
}
/** 指定行の直前の非空行（escape-hatch を前行に置くケース用）。 */
function prevNonBlank(src, line) {
  const lines = src.split('\n');
  for (let i = line - 2; i >= 0; i--) {
    if (lines[i].trim() !== '') return lines[i];
  }
  return '';
}

/** プロジェクト走査素材（1 回だけ集める）。`code` はコメント空白化済み（誤検知防止）。 */
function gather(root) {
  const appDir = resolveAppDir(root);
  const libDirs = resolveSourceDirs(root, 'lib');
  const compDirs = resolveSourceDirs(root, 'components');
  const srcRoots = [appDir, ...libDirs, ...compDirs].filter(Boolean);
  const seen = new Set();
  const sources = [];
  for (const d of srcRoots) {
    for (const abs of walk(d, (_f, name) => isSource(name))) {
      if (seen.has(abs)) continue;
      seen.add(abs);
      const src = read(abs);
      sources.push({ abs, rel: rel(root, abs), base: path.basename(abs), src, code: stripComments(src) });
    }
  }
  return { root, appDir, sources };
}

const inDir = (relPath, ...names) =>
  names.some((n) => relPath === n || relPath.startsWith(n + '/') || relPath.startsWith('src/' + n + '/'));
const isRoute = (s) => /(^|\/)route\.(ts|js|tsx|jsx)$/.test(s.rel);
const isApiRoute = (s) => isRoute(s) && (s.rel.includes('/api/') || s.rel.startsWith('app/api/') || s.rel.startsWith('src/app/api/'));
const isPage = (s) => /(^|\/)page\.(tsx|jsx|ts|js)$/.test(s.rel);
const isLayout = (s) => /(^|\/)layout\.(tsx|jsx)$/.test(s.rel);

// ---- checks ---------------------------------------------------------------

const S1 = {
  rule: 'S1', tier: 'Tier-1', title: '依存方向・barrel ゼロ',
  run({ sources }) {
    const f = [];
    for (const s of sources) {
      if (!inDir(s.rel, 'lib', 'components')) continue;
      for (const hit of matchLines(s.code, /from\s+['"]@\/app(\/|['"])/)) {
        f.push({ severity: 'error', file: s.rel, line: hit.line, message: `lib/components が @/app を import（依存方向違反）` });
      }
      if (/(^|\/)index\.(ts|tsx)$/.test(s.rel) && !/barrel-ok/.test(s.src)) {
        const reexport = matchLines(s.code, /export\s+(\*|\{[^}]*\})\s+from/);
        if (reexport.length) f.push({ severity: 'error', file: s.rel, line: reexport[0].line, message: `barrel（re-export 集約 index）。public entry なら // barrel-ok を明記` });
      }
    }
    return f;
  },
};

const S2 = {
  rule: 'S2', tier: 'Tier-1', title: 'route は prisma 直叩き禁止・DAL 経由',
  // `from '@/lib/prisma'` / 動的 `import('@/lib/prisma')` / subpath `@/lib/prisma/...`（spec の grep は substring）
  importRe: /(from\s*|import\s*\(\s*|require\s*\(\s*)['"]@\/lib\/prisma(\/[^'"]*)?['"]/,
  run({ sources }) {
    const f = [];
    for (const s of sources) {
      if (!isApiRoute(s)) continue;
      for (const hit of matchLines(s.code, this.importRe)) {
        const text = s.code.split('\n')[hit.line - 1] || '';
        const isDynamic = /\b(import|require)\s*\(/.test(hit.text);
        if (!isDynamic) {
          // type-only import は runtime DB 依存ゼロ → S2 対象外（pack 自身が `type Tx = Prisma.TransactionClient` を export）
          if (/^\s*import\s+type\b/.test(text)) continue;
          const braces = text.match(/import\s*\{([^}]*)\}/);
          if (braces && braces[1].split(',').filter((x) => x.trim()).every((x) => /^\s*type\s/.test(x))) continue;
        }
        f.push({ severity: 'error', file: s.rel, line: hit.line, message: `route が @/lib/prisma を直接 import（DAL 経由にする）` });
      }
      const lines = s.src.split('\n').length;
      if (lines > 80) f.push({ severity: 'warn', file: s.rel, line: lines, message: `route.ts が ${lines} 行（SHOULD: 概ね ≤80。ロジックを DAL へ）` });
    }
    return f;
  },
};

const S3 = {
  rule: 'S3', tier: 'Tier-1', title: 'server-first（in-page fetch しない）',
  run({ sources }) {
    const f = [];
    for (const s of sources) {
      if (!isPage(s)) continue;
      if (/useEffect\s*\(/.test(s.code) && /\bfetch\s*\(/.test(s.code)) {
        f.push({ severity: 'error', file: s.rel, line: matchLines(s.code, /useEffect\s*\(/)[0].line, message: `page が useEffect + fetch で自前データ取得（server boundary から props で渡す）` });
      }
    }
    return f;
  },
};

const S4 = {
  rule: 'S4', tier: 'Tier-1', title: 'mutation 面 = 列挙可能な単一機構',
  run({ root, sources }) {
    const f = [];
    for (const s of sources) {
      if (!/['"]use server['"]/.test(s.code)) continue;
      // inline 判定は**インデント非依存**: module の先頭文が 'use server' か（= enumerator の単一定義）で分類する。
      const moduleLevel = enumr.isModuleLevelServerActionFile(s.code);
      const directives = matchLines(s.code, /['"]use server['"]/);
      const dirLine = moduleLevel && directives.length ? directives[0].line : -1;
      for (const d of directives) {
        if (d.line === dirLine) continue; // module ディレクティブ本体はスキップ
        // module ディレクティブ以外の 'use server' は inline クロージャ（col-0 / 同一行も含む）
        f.push({ severity: 'error', file: s.rel, line: d.line, message: `inline 'use server' クロージャ（grep 列挙不能 → module-level actions.ts に出す）` });
      }
      if (moduleLevel && s.base !== 'actions.ts') {
        f.push({ severity: 'error', file: s.rel, line: dirLine > 0 ? dirLine : 1, message: `module-level 'use server' は actions.ts に集約する（現: ${s.base}）` });
      }
    }
    // 情報: mutation 面の正準カウント（trigger taxonomy）
    f._info = { mutationSurface: enumr.enumerateMutations(root).length };
    return f;
  },
};

const S5 = {
  rule: 'S5', tier: 'Tier-1', title: '認証コア（単一 helper・role enum）',
  // 生セッション読み取りトークン。PJ は自分の auth ライブラリの reader を追記する。
  // 既定は session 固有のもの。Auth.js v5 の `auth()` は語が一般的すぎて誤検知しうるため
  // 既定に含めず PJ ごとに追記する（README 参照）。
  rawSessionTokens: ['getServerSession', 'unstable_getServerSession', 'currentUser', 'getSession'],
  run({ sources }) {
    const f = [];
    const tokenRe = new RegExp(`\\b(${this.rawSessionTokens.join('|')})\\s*\\(`);
    for (const s of sources) {
      // seam = lib/**/auth/ ディレクトリ or 単一ファイル lib/auth.ts | lib/session.ts（spec は「単一 helper」のみ要求）
      const inAuthHelper = inDir(s.rel, 'lib') && (/(^|\/)auth\//.test(s.rel) || /(^|\/)(auth|session)\.(ts|tsx|js|jsx)$/.test(s.rel));
      if (!inAuthHelper) {
        for (const hit of matchLines(s.code, tokenRe)) {
          f.push({ severity: 'error', file: s.rel, line: hit.line, message: `生セッション読み取り（${hit.text.trim()}）が auth helper の外（単一 helper 経由にする）` });
        }
      }
      for (const hit of matchLines(s.code, /\.?\brole\s*[!=]==?\s*['"]/)) {
        f.push({ severity: 'error', file: s.rel, line: hit.line, message: `role を文字列リテラルで比較（Prisma enum で比較する）` });
      }
    }
    return f;
  },
};

const S6 = {
  rule: 'S6', tier: 'Tier-1', title: 'object-level 認可（DAL で tenant/owner スコープ）',
  scopeKeys: ['companyId', 'tenantId', 'organizationId', 'ownerId', 'userId', 'authorId', 'accountId'],
  // 単一エンティティの read/write（IDOR-prone）。findMany 等の一覧は対象外（list は別問題）。
  opRe: /prisma\.\w+\.(findUnique|findFirst|updateMany|update|deleteMany|delete)\s*\(\s*\{[\s\S]{0,200}?\}\s*\)/,
  run({ sources }) {
    // 存在=HARD だが「全 data-path 網羅」は SOFT（data-flow 解析が要る）→ warn で候補可視化。
    const f = [];
    const scopeRe = new RegExp(`\\b(${this.scopeKeys.join('|')})\\b`);
    for (const s of sources) {
      if (!inDir(s.rel, 'lib')) continue;
      if (!/['"]@\/lib\/prisma(\/[^'"]*)?['"]/.test(s.code)) continue;
      for (const hit of matchLines(s.code, this.opRe)) {
        if (scopeRe.test(hit.text)) continue;
        // escape hatch: 冪等性キー / 署名 gated 等の正当な非テナント取得は // authz-ok を明記（同行 or 直前行）
        if (/authz-ok/.test(rawLine(s.src, hit.line)) || /authz-ok/.test(prevNonBlank(s.src, hit.line))) continue;
        f.push({ severity: 'warn', file: s.rel, line: hit.line, message: `単一エンティティ read/write が tenant/owner スコープを欠く可能性（${this.scopeKeys.slice(0, 4).join('/')} 等で絞る・正当なら // authz-ok）` });
      }
    }
    return f;
  },
};

const S7 = {
  rule: 'S7', tier: 'Tier-1', title: 'validation 単一ソース（route 内 z.object 禁止）',
  run({ sources }) {
    const f = [];
    for (const s of sources) {
      if (!isApiRoute(s)) continue;
      // `z.object(` / `z\n.object(`（Prettier の改行チェーン）両対応
      for (const hit of matchLines(s.code, /\bz\s*\.\s*object\s*\(/)) {
        f.push({ severity: 'error', file: s.rel, line: hit.line, message: `route 内に z.object literal（lib/validations から named schema を import する）` });
      }
    }
    return f;
  },
};

const H1 = {
  rule: 'H1', tier: 'Tier-2', title: 'データ層（Prisma singleton）',
  run({ sources }) {
    const f = [];
    for (const s of sources) {
      const isSingleton = s.base === 'prisma.ts' && inDir(s.rel, 'lib');
      for (const hit of matchLines(s.code, /new\s+PrismaClient\b/)) {
        if (!isSingleton) f.push({ severity: 'error', file: s.rel, line: hit.line, message: `new PrismaClient が singleton（lib/prisma.ts）の外（追加インスタンス禁止）` });
      }
      for (const hit of matchLines(s.code, /console\.\w+\([^)]*DATABASE_URL/)) {
        f.push({ severity: 'error', file: s.rel, line: hit.line, message: `接続文字列（DATABASE_URL）を console 出力している` });
      }
    }
    return f;
  },
};

const H3 = {
  rule: 'H3', tier: 'Tier-2', title: 'rendering & framework files',
  run({ sources }) {
    const f = [];
    const errorSiblings = new Set(sources.filter((s) => /(^|\/)error\.(tsx|jsx)$/.test(s.rel)).map((s) => path.dirname(s.rel)));
    for (const s of sources) {
      if (isPage(s)) {
        for (const hit of matchLines(s.code, /export\s+const\s+dynamic\s*=\s*['"]force-dynamic['"]/)) {
          f.push({ severity: 'warn', file: s.rel, line: hit.line, message: `page の常時 force-dynamic（是正対象。正当なら理由コメント）` });
        }
        // resilience 境界（SHOULD）: データ取得（await）を伴う page に error 境界が無い
        if (/\bawait\b/.test(s.code) && !errorSiblings.has(path.dirname(s.rel))) {
          f.push({ severity: 'warn', file: s.rel, line: 1, message: `データ取得 segment に error.tsx が無い（SHOULD: 部分失敗を UI 境界で受ける）` });
        }
      }
      if (isLayout(s)) {
        for (const hit of matchLines(s.code, /usePathname\s*\(/)) {
          f.push({ severity: 'warn', file: s.rel, line: hit.line, message: `layout が usePathname で分岐（route group + per-segment layout で表現する）` });
        }
      }
    }
    return f;
  },
};

const H4 = {
  rule: 'H4', tier: 'Tier-2', title: '構造ハイジーン',
  run({ root, sources }) {
    const f = [];
    // tracked tree に .backup / .tmp を残さない
    for (const abs of walk(root, (_f, name) => /\.(backup|tmp)$/.test(name))) {
      f.push({ severity: 'error', file: rel(root, abs), line: 1, message: `.backup / .tmp が tree に残っている` });
    }
    // server 専用ロジック（prisma 利用 lib）に import 'server-only' が無い
    for (const s of sources) {
      if (!inDir(s.rel, 'lib')) continue;
      if (s.base === 'prisma.ts') continue;
      if (/from\s+['"]@\/lib\/prisma['"]/.test(s.code) && !/['"]server-only['"]/.test(s.code)) {
        f.push({ severity: 'warn', file: s.rel, line: 1, message: `prisma 利用の server 専用ロジックに import 'server-only' が無い` });
      }
    }
    return f;
  },
};

const CHECKS = [S1, S2, S3, S4, S5, S6, S7, H1, H3, H4];

/** 全 check を 1 プロセスで実行（WSL の vitest hang を避ける）。 */
function runAll(root) {
  const ctx = gather(root);
  const results = [];
  for (const c of CHECKS) {
    const findings = c.run.call(c, ctx) || [];
    results.push({ rule: c.rule, tier: c.tier, title: c.title, findings, info: findings._info || null });
  }
  return results;
}

module.exports = { CHECKS, runAll, gather };
