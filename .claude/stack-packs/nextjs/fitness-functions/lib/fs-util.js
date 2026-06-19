// fs-util.js — 依存ゼロのファイル走査ヘルパー（fitness / enumerator 共有）
// 下流PJにそのままコピーして使える（Node 標準のみ・外部依存なし）。

const fs = require('fs');
const path = require('path');

const SKIP_DIRS = new Set([
  'node_modules', '.git', '.next', 'dist', 'build', 'coverage',
  '.turbo', '.vercel', 'out', '.cache',
  // ccs ツール群（下流に同梱される pack 自身の fixtures 等）は PJ の source ではないので走査しない。
  // これが無いと H4 の .backup 走査が pack の fixtures/violations/h4/stale.backup を誤検知する（greenfield 検証で発見）。
  '.claude',
]);

/** ディレクトリを再帰走査し、条件に合うファイルの絶対パスを返す。 */
function walk(dir, filter = () => true) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    if (ent.isDirectory()) {
      if (SKIP_DIRS.has(ent.name)) continue;
      out.push(...walk(path.join(dir, ent.name), filter));
    } else if (ent.isFile()) {
      const full = path.join(dir, ent.name);
      if (filter(full, ent.name)) out.push(full);
    }
  }
  return out;
}

/** ファイルを読む（失敗時は空文字）。 */
function read(file) {
  try { return fs.readFileSync(file, 'utf8'); } catch { return ''; }
}

/** Next.js の app ディレクトリを解決（root `app/` または `src/app/`）。無ければ null。 */
function resolveAppDir(root) {
  for (const cand of ['app', path.join('src', 'app')]) {
    const p = path.join(root, cand);
    if (fs.existsSync(p)) return p;
  }
  return null;
}

/** Next.js の lib/components ディレクトリ候補（root or src/）を返す。 */
function resolveSourceDirs(root, name) {
  const dirs = [];
  for (const cand of [name, path.join('src', name)]) {
    const p = path.join(root, cand);
    if (fs.existsSync(p)) dirs.push(p);
  }
  return dirs;
}

/** TS/TSX ソースファイルか。 */
function isSource(name) {
  return /\.(ts|tsx|js|jsx|mjs|cjs)$/.test(name) && !/\.d\.ts$/.test(name);
}

/** ルートからの相対パス（表示用・OS 非依存に / 区切り）。 */
function rel(root, file) {
  return path.relative(root, file).split(path.sep).join('/');
}

/**
 * コメントを空白化（行番号は保持）。文字列・テンプレート・**正規表現リテラル**を保護する。
 * methodology の「コメントを一次ソースにしない」を checker 自身に適用するための前処理。
 * （コメント内に書いた規約名 `usePathname()` / `new PrismaClient` 等の誤検知を防ぐ）
 *
 * 正規表現リテラルの保護が要る理由: `/^https?:\/\//` のような URL 正規表現が無いと、
 * `//`（プロトコルの実体ではなく `\/\/`）や除算と混同して行コメント扱いになり、
 * 同一行の実違反（例: `&& role === 'admin'`）を黙って潰す（HARD ルールの false-negative）。
 *
 * 正規表現 vs 除算の判別: 直前の有意文字が「式を終えられない」位置（= 演算子・開き括弧・行頭等）
 * なら正規表現開始とみなす（標準的なヒューリスティック）。`return /re/` 等のキーワード直後は
 * 除算扱いになるが、正規表現中の `//` は必ず `\/\/` とエスケープされるため bare `//` は生じず実害なし。
 */
function stripComments(src) {
  let out = '';
  let i = 0;
  const n = src.length;
  let state = 'code'; // code | line | block | sq | dq | tpl | regex | class
  let lastSig = ''; // 直前の有意な code 文字（正規表現/除算の判別用）
  const regexCanStart = () =>
    lastSig === '' || '(,=:[!&|?{;}'.includes(lastSig) || /[+\-*%<>^~]/.test(lastSig);
  while (i < n) {
    const c = src[i];
    const c2 = src[i + 1];
    if (state === 'code') {
      if (c === '/' && c2 === '/') { state = 'line'; out += '  '; i += 2; continue; }
      if (c === '/' && c2 === '*') { state = 'block'; out += '  '; i += 2; continue; }
      if (c === '/' && regexCanStart()) { state = 'regex'; out += c; lastSig = '/'; i++; continue; }
      if (c === "'") { state = 'sq'; out += c; lastSig = c; i++; continue; }
      if (c === '"') { state = 'dq'; out += c; lastSig = c; i++; continue; }
      if (c === '`') { state = 'tpl'; out += c; lastSig = c; i++; continue; }
      out += c;
      if (!/\s/.test(c)) lastSig = c;
      i++; continue;
    }
    if (state === 'line') { if (c === '\n') { state = 'code'; out += c; } else out += ' '; i++; continue; }
    if (state === 'block') { if (c === '*' && c2 === '/') { state = 'code'; out += '  '; i += 2; } else { out += (c === '\n' ? '\n' : ' '); i++; } continue; }
    if (state === 'regex') {
      out += c;
      if (c === '\\') { out += (src[i + 1] || ''); i += 2; continue; }
      if (c === '[') { state = 'class'; i++; continue; }       // 文字クラス内の `/` は区切りでない
      if (c === '/') { state = 'code'; lastSig = 'x'; i++; continue; } // 終了。式が終わった扱い
      i++; continue;
    }
    if (state === 'class') {
      out += c;
      if (c === '\\') { out += (src[i + 1] || ''); i += 2; continue; }
      if (c === ']') { state = 'regex'; i++; continue; }
      i++; continue;
    }
    // 文字列/テンプレート: 内容は保持、エスケープを跨ぐ
    out += c;
    if (c === '\\') { out += (src[i + 1] || ''); i += 2; continue; }
    if ((state === 'sq' && c === "'") || (state === 'dq' && c === '"') || (state === 'tpl' && c === '`')) { state = 'code'; lastSig = c; }
    i++;
  }
  return out;
}

/**
 * 文字列・テンプレート・正規表現リテラルの**内部を空白化**（区切り文字は残す・長さと改行は保持）。
 * `stripComments` はコメントを消すが**リテラル内容は保持**する（規約名が文字列に出ても保持される）。
 * 一方、波括弧マッチや `prisma.x.op(` 抽出を行う側は、リテラル内の `}` や `prisma.x.op(` を
 * コードと誤認してはいけない（敵対検証で実証: `const t = "}"` が関数本体を途中で打ち切る /
 * `"call prisma.delta.create("` 文字列が phantom table を生む / `const HELP = "verifySignature()"`
 * が認可ゲートを誤検知）。本関数を通すと**コードの識別子・演算子・波括弧は残り、リテラル内部だけ空白**になる。
 * 使い方は `blankLiterals(stripComments(src))`（コメント除去 → リテラル内部空白化）。
 * `stripComments` と同じ正規表現/除算ヒューリスティックを共有する。
 */
function blankLiterals(src) {
  let out = '';
  let i = 0;
  const n = src.length;
  let state = 'code'; // code | line | block | sq | dq | tpl | regex | class
  let lastSig = '';
  // テンプレートリテラルの `${ ... }` 補間部は**コード**（保持する）。ネスト追跡用スタック。
  const tplStack = []; // 各補間の波括弧深さ（補間内の object `{}` を跨いで終端 `}` を判定）
  const regexCanStart = () =>
    lastSig === '' || '(,=:[!&|?{;}'.includes(lastSig) || /[+\-*%<>^~]/.test(lastSig);
  const blank = (c) => (c === '\n' ? '\n' : ' ');
  while (i < n) {
    const c = src[i];
    const c2 = src[i + 1];
    if (state === 'code') {
      // テンプレート補間内: 終端 `}`（深さ 0）で tpl に戻る。object の `{}` は深さで吸収。
      if (tplStack.length) {
        const fr = tplStack[tplStack.length - 1];
        if (c === '{') { fr.depth++; out += c; lastSig = '{'; i++; continue; }
        if (c === '}') {
          if (fr.depth === 0) { tplStack.pop(); state = 'tpl'; out += c; lastSig = '}'; i++; continue; }
          fr.depth--; out += c; lastSig = '}'; i++; continue;
        }
      }
      if (c === '/' && c2 === '/') { state = 'line'; out += '  '; i += 2; continue; }
      if (c === '/' && c2 === '*') { state = 'block'; out += '  '; i += 2; continue; }
      if (c === '/' && regexCanStart()) { state = 'regex'; out += c; lastSig = '/'; i++; continue; }
      if (c === "'") { state = 'sq'; out += c; lastSig = c; i++; continue; }
      if (c === '"') { state = 'dq'; out += c; lastSig = c; i++; continue; }
      if (c === '`') { state = 'tpl'; out += c; lastSig = c; i++; continue; }
      out += c;
      if (!/\s/.test(c)) lastSig = c;
      i++; continue;
    }
    if (state === 'line') { if (c === '\n') { state = 'code'; out += c; } else out += ' '; i++; continue; }
    if (state === 'block') { if (c === '*' && c2 === '/') { state = 'code'; out += '  '; i += 2; } else { out += blank(c); i++; } continue; }
    if (state === 'regex') {
      if (c === '\\') { out += '  '; i += 2; continue; }          // エスケープ対も空白化
      if (c === '[') { state = 'class'; out += ' '; i++; continue; }
      if (c === '/') { state = 'code'; out += c; lastSig = 'x'; i++; continue; } // 終了スラッシュは残す
      out += blank(c); i++; continue;
    }
    if (state === 'class') {
      if (c === '\\') { out += '  '; i += 2; continue; }
      if (c === ']') { state = 'regex'; out += ' '; i++; continue; }
      out += blank(c); i++; continue;
    }
    if (state === 'sq' || state === 'dq') {
      if (c === '\\') { out += '  '; i += 2; continue; }
      if ((state === 'sq' && c === "'") || (state === 'dq' && c === '"')) { state = 'code'; out += c; lastSig = c; i++; continue; }
      out += blank(c); i++; continue;
    }
    // tpl: 静的部は空白化、`${` で補間（コード）へ、区切りは残す
    if (c === '\\') { out += '  '; i += 2; continue; }
    if (c === '`') { state = 'code'; out += c; lastSig = c; i++; continue; }
    if (c === '$' && c2 === '{') { tplStack.push({ depth: 0 }); state = 'code'; out += '${'; lastSig = '{'; i += 2; continue; }
    out += blank(c); i++;
  }
  return out;
}

module.exports = {
  walk, read, resolveAppDir, resolveSourceDirs, isSource, rel, stripComments, blankLiterals, SKIP_DIRS,
};
