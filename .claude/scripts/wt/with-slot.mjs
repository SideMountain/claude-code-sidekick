#!/usr/bin/env node
// =============================================================================
// with-slot.mjs — heavy / runtime コマンドのラッパー（ADR-0035 決定 3・4・5）
//
//   取得 → 実行 → finally で必ず解放。
//
// timeout は `acquireTimeoutMs`（slot の取得待ち）だけを持つ。取得後のコマンド
// 寿命には timeout を持たない — 実装すると Windows を含む process tree の終了・
// シグナル転送・孤児回収まで必要になり、「プロセスの自動 kill は作らない」と
// 正面から矛盾する。コマンドの寿命は呼び出し元・CI・既存の timeout 機構へ委譲し、
// ここは子の終了を待って枠を返すだけにする。
//
// 使い方:
//   node with-slot.mjs --kind heavy [--label x] [--acquire-timeout-ms N] -- <cmd> [args...]
// =============================================================================

import { spawn } from "node:child_process";
import fs from "node:fs";
import { detectDomain, slotsDir } from "./domain.mjs";
import { loadLimits } from "./policy.mjs";
import { acquire, cellPath, hashToken, release, reclaimStale } from "./slots.mjs";

const EXIT = { USAGE: 2, RESOURCE_BUSY: 5, SPAWN_FAILED: 7, RELEASE_FAILED: 8 };
const DEFAULT_ACQUIRE_TIMEOUT_MS = 30 * 60 * 1000;
const POLL_MS = 250;

const ENV_KIND = "CCS_WT_SLOT_KIND";
const ENV_INDEX = "CCS_WT_SLOT_INDEX";
const ENV_TOKEN = "CCS_WT_SLOT_TOKEN";
// 上の 3 つは「N 本のうち 1 本を保持している」ことを示すだけで、排他の証明ではない。
// 子プロセスの並列度をこの値から決めない（MVP では占有数を子へ渡さない）。

function usage(msg) {
  if (msg) process.stderr.write(`[with-slot] ${msg}\n`);
  process.stderr.write(
    "Usage: with-slot.mjs --kind heavy|runtime [--label <s>] [--acquire-timeout-ms <ms>] -- <command> [args...]\n",
  );
  process.exit(EXIT.USAGE);
}

function parseArgs(argv) {
  const sep = argv.indexOf("--");
  if (sep < 0 || sep === argv.length - 1) usage("`--` の後ろに実行するコマンドが必要です");
  const opts = { kind: null, label: "", acquireTimeoutMs: DEFAULT_ACQUIRE_TIMEOUT_MS };
  for (let i = 0; i < sep; i += 1) {
    const a = argv[i];
    if (a === "--kind") opts.kind = argv[++i];
    else if (a === "--label") opts.label = argv[++i] ?? "";
    else if (a === "--acquire-timeout-ms") opts.acquireTimeoutMs = Number(argv[++i]);
    else usage(`不明なオプション: ${a}`);
  }
  if (opts.kind !== "heavy" && opts.kind !== "runtime") usage("--kind は heavy か runtime");
  if (!Number.isFinite(opts.acquireTimeoutMs) || opts.acquireTimeoutMs < 0)
    usage("--acquire-timeout-ms は 0 以上の数値");
  return { ...opts, command: argv[sep + 1], args: argv.slice(sep + 2) };
}

/**
 * 再入の判定（決定 3）。素通しの条件を boolean マーカーにしない —
 * 真偽値だけだと、古い環境変数の残骸や手動設定でも素通しが成立し、
 * slot を消費しないまま重い処理が走る。
 * kind / index / 秘密 token が cell の releaseTokenHash と照合できたときだけ
 * 再入と認める。照合できなければ素通しせず、通常の取得へ進む。
 */
function reentrantIndex(kind, env, dir) {
  if (env[ENV_KIND] !== kind) return null;
  const index = Number(env[ENV_INDEX]);
  const token = env[ENV_TOKEN];
  if (!Number.isInteger(index) || index < 0 || !token) return null;
  try {
    const cell = JSON.parse(fs.readFileSync(cellPath(dir, index), "utf8"));
    if (cell && cell.kind === kind && cell.releaseTokenHash === hashToken(token)) return index;
  } catch {
    /* cell 不在・JSON 破損はいずれも「照合できない」 */
  }
  return null;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const domain = detectDomain();
  const dir = slotsDir(opts.kind);
  const limits = loadLimits();
  const limit = limits[opts.kind];

  // --- 再入: 外側が owner。内側は取得も解放もしない ---
  const reIdx = reentrantIndex(opts.kind, process.env, dir);
  if (reIdx !== null) {
    process.stderr.write(`[with-slot] reentrant (kind=${opts.kind} index=${reIdx}) — 取得せず素通し\n`);
    const code = await run(opts, process.env);
    process.exit(code);
  }

  // --- 取得: 待つかどうかは呼び出し側が決める（既定はポーリング待ち） ---
  const deadline = Date.now() + opts.acquireTimeoutMs;
  let got = null;
  for (;;) {
    got = acquire({ kind: opts.kind, limit, owner: `pid:${process.pid}`, domain, label: opts.label, dir });
    if (got.ok) break;
    // 満杯のときだけ stale 回収を試みる（走査量は上限 N にのみ比例する）。
    reclaimStale({ kind: opts.kind, limit, dir, selfDomain: domain });
    got = acquire({ kind: opts.kind, limit, owner: `pid:${process.pid}`, domain, label: opts.label, dir });
    if (got.ok) break;
    if (Date.now() >= deadline) {
      process.stderr.write(
        `[with-slot] RESOURCE_BUSY: ${opts.kind} の枠 ${limit} 本がすべて占有中（acquireTimeoutMs 超過）\n`,
      );
      process.exit(EXIT.RESOURCE_BUSY);
    }
    await sleep(POLL_MS);
  }

  const childEnv = {
    ...process.env,
    [ENV_KIND]: opts.kind,
    [ENV_INDEX]: String(got.index),
    [ENV_TOKEN]: got.token,
  };

  let code = 1;
  let released = { ok: false, reason: "not-attempted" };
  try {
    code = await run(opts, childEnv);
  } finally {
    // 正常終了・捕捉可能シグナルのいずれもここを通る。
    // SIGKILL / クラッシュではここは走らず、stale recovery だけが回収する。
    released = release({ kind: opts.kind, index: got.index, token: got.token, dir });
  }
  if (!released.ok) {
    // 子コマンドが成功しても、枠が埋まったままなら成功として終わらせない。
    // これを子の exit code に吸収させると「コマンド成功 + slot 残留」が緑になる。
    process.stderr.write(
      `[with-slot] slot を解放できませんでした（${released.reason}）。` +
        `kind=${opts.kind} index=${got.index} — 枠が占有されたまま残っています\n`,
    );
    process.exit(EXIT.RELEASE_FAILED);
  }
  process.exit(code);
}

function run(opts, env) {
  return new Promise((resolve) => {
    // Windows では node_modules/.bin の shim が .cmd であり、shell:false の spawn は
    // EINVAL で失敗する（existsSync は大小無視 FS のため事前検出もできない）。
    // shell を有効にして回避せず、node は process.execPath で直接起動する。
    const isNode = opts.command === "node" || opts.command === "node.exe";
    const cmd = isNode ? process.execPath : opts.command;
    const child = spawn(cmd, opts.args, { stdio: "inherit", env, shell: false });

    const forward = (sig) => {
      try {
        child.kill(sig);
      } catch {
        /* 既に終了 */
      }
    };
    process.on("SIGINT", () => forward("SIGINT"));
    process.on("SIGTERM", () => forward("SIGTERM"));

    child.on("error", (e) => {
      process.stderr.write(
        `[with-slot] 子プロセスを起動できません: ${e.code || e.message}\n` +
          `  shell は有効化しません。実行可能ファイルを直接指定してください` +
          `（Windows の .cmd shim は shell:false で起動できません）。\n`,
      );
      resolve(EXIT.SPAWN_FAILED);
    });
    child.on("close", (c, sig) => resolve(sig ? 1 : (c ?? 1)));
  });
}

main().catch((e) => {
  process.stderr.write(`[with-slot] 想定外の失敗: ${e && e.stack ? e.stack : e}\n`);
  process.exit(EXIT.SPAWN_FAILED);
});
