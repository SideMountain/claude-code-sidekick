// =============================================================================
// run.mjs — Resource Governor の CLI 境界カナリア（ADR-0035 Phase 4B）
//
// 生の fixture（wt-slots / wt-concurrency）は slots.mjs の API を直接叩く。
// ここだけが **with-slot.mjs の CLI 境界**を実プロセスで通す:
//   引数解析 → 取得 → 子への env 受け渡し → 子の起動 → finally の解放 → 終了コード
//
// 有界化を wall 時間の閾値で行わない。runner の混雑で偽陰性になり、固定 sleep を
// 合否に使うのと同じ失敗をする。境界は次の 4 つだけが担う:
//   1. prober の取得期限（--acquire-timeout-ms）
//   2. holder の内部 deadline（解放マーカーが来なくても必ず終わる）
//   3. 自分が spawn した子だけを回収する全体 deadline
//   4. workflow 側の timeout-minutes
// wall は RECORD として出力するだけで、合否には一切使わない。
//
// 隔離: store も policy も suite root 配下へ向ける。利用者の実 store・実 policy・
// OS 全体の tmp は読み書きも走査もしない。
//
// 使い方（replay.sh から起動される）:
//   node run.mjs <REPO>                     … カナリア本体
//   node run.mjs --workload --marker <p> …  … with-slot が起動する被計測コマンド
// =============================================================================

import { spawn } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SELF = fileURLToPath(import.meta.url);

// with-slot.mjs の終了コード（with-slot.mjs の EXIT と一致させる）
const EXIT_RESOURCE_BUSY = 5;

// -----------------------------------------------------------------------------
// workload モード — with-slot の子として起動される側
// -----------------------------------------------------------------------------

function parseKV(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i].startsWith("--")) out[argv[i]] = argv[i + 1] ?? "";
  }
  return out;
}

function sleepSync(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

/** 親に部分内容を読ませない（tmp → rename）。 */
function writeJsonAtomic(file, value) {
  const tmp = `${file}.tmp-${process.pid}-${crypto.randomBytes(4).toString("hex")}`;
  fs.writeFileSync(tmp, JSON.stringify(value));
  fs.renameSync(tmp, file);
}

function workloadMain(argv) {
  const opt = parseKV(argv);
  // 「枠を持って動いている子が、実際に何を渡されたか」だけを記録する。
  writeJsonAtomic(opt["--marker"], {
    kind: process.env.CCS_WT_SLOT_KIND ?? null,
    index: process.env.CCS_WT_SLOT_INDEX ?? null,
    token: process.env.CCS_WT_SLOT_TOKEN ?? null,
    pid: process.pid,
  });

  const holdUntil = opt["--hold-until"];
  if (!holdUntil) return 0;

  // 解放マーカーで終わる。来なくても内部 deadline で必ず終わる（吊られない）。
  const deadline = Date.now() + Number(opt["--hold-deadline-ms"] || 20_000);
  for (;;) {
    if (fs.existsSync(holdUntil)) return 0;
    if (Date.now() >= deadline) {
      process.stderr.write("[workload] hold deadline に到達したため解放します\n");
      return 0;
    }
    sleepSync(25);
  }
}

if (process.argv[2] === "--workload") {
  process.exit(workloadMain(process.argv.slice(3)));
}

// -----------------------------------------------------------------------------
// カナリア本体
// -----------------------------------------------------------------------------

const REPO = process.argv[2];
if (!REPO) {
  console.error("FAIL     usage  run.mjs <REPO>");
  process.exit(2);
}
const WITH_SLOT = path.join(REPO, ".claude", "scripts", "wt", "with-slot.mjs");

let failed = 0;
function ok(name, cond, detail = "") {
  if (cond) console.log(`PASS     ${name}${detail ? "  " + detail : ""}`);
  else {
    console.error(`FAIL     ${name}${detail ? "  " + detail : ""}`);
    failed += 1;
  }
}
function record(name, detail) {
  console.log(`RECORD   ${name}  ${detail}`);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// スイート専用 root。store も policy もこの配下に閉じる。
const SUITE_ROOT = fs.mkdtempSync(path.join(os.tmpdir(), "ccs-wt-canary-"));
const STORE_ROOT = path.join(SUITE_ROOT, "store");
const POLICY_FILE = path.join(SUITE_ROOT, "policy.json");
const MARKERS = path.join(SUITE_ROOT, "markers");
fs.mkdirSync(MARKERS, { recursive: true });

// 上限は**組み込み既定に依存させず**明示 policy で固定する。既定値が将来変われば
// カナリアの競合条件（heavy=1）が黙って消えるため。env は下げる方向にしか効かない
// ので、policy が上限の唯一の根拠になる。
fs.writeFileSync(POLICY_FILE, `${JSON.stringify({ heavy: 1, runtime: 1 })}\n`);
const HEAVY_LIMIT = 1;

const CHILD_ENV = {
  ...process.env,
  CCS_WT_STORE: STORE_ROOT,
  CCS_WT_POLICY: POLICY_FILE,
};
// 再入マーカーは引き継がない。このカナリア自身が将来 with-slot 配下で
// 実行されると、継承した kind/index/token が再入判定に掛かりうる。素通しに
// なればカナリアは取得も解放も検査しなくなり、**緑のまま意味を失う**。
for (const k of ["CCS_WT_SLOT_KIND", "CCS_WT_SLOT_INDEX", "CCS_WT_SLOT_TOKEN"]) delete CHILD_ENV[k];

// 自分が spawn した子だけを回収する。全体 deadline は病的なケースの保険であり、
// 通常経路は上の 1〜2 で終わる。
const GLOBAL_DEADLINE_MS = 120_000;
const alive = new Set();
let abortedByDeadline = false;
const globalTimer = setTimeout(() => {
  abortedByDeadline = true;
  for (const c of alive) {
    try {
      c.kill("SIGKILL");
    } catch {
      /* 既に終了 */
    }
  }
}, GLOBAL_DEADLINE_MS);

/** with-slot 経由でカナリア workload を起動する（＝ Governor の CLI 境界を通す）。 */
function spawnGoverned({ label, acquireTimeoutMs, workloadArgs }) {
  const args = [
    WITH_SLOT,
    "--kind",
    "heavy",
    "--label",
    label,
    "--acquire-timeout-ms",
    String(acquireTimeoutMs),
    "--",
    // with-slot は "node" を process.execPath へ解決する。PATH 解決と
    // Windows の .cmd shim を避けるため、必ずこの形で渡す。
    "node",
    SELF,
    "--workload",
    ...workloadArgs,
  ];
  const startedAt = Date.now();
  const child = spawn(process.execPath, args, { env: CHILD_ENV, stdio: ["ignore", "pipe", "pipe"] });
  alive.add(child);
  let out = "";
  let err = "";
  child.stdout.on("data", (d) => {
    out += d;
  });
  child.stderr.on("data", (d) => {
    err += d;
  });
  const done = new Promise((resolve) => {
    child.on("close", (code, signal) => {
      alive.delete(child);
      resolve({ code, signal, out, err, wallMs: Date.now() - startedAt });
    });
  });
  return { child, done };
}

async function waitForFile(file, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    if (fs.existsSync(file)) return true;
    if (Date.now() >= deadline || abortedByDeadline) return false;
    await sleep(25);
  }
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

/**
 * 隔離 store 配下を再帰走査し、ACTIVE な資源が残っていないことを確かめる。
 *
 * 既知の名前（cell / quarantine）だけを数えない — 列挙は実装が名前を増やした
 * 瞬間に偽陰性になる。「残ってよいのは空の足場ディレクトリだけ」という
 * 意味論で判定し、それ以外は全部 residue とする（fail-closed）。
 *   - 通常ファイルが 1 つでも残っていれば residue（cell・token 子・quarantine 断片）
 *   - `.claim-*` ディレクトリは空でも占有を意味するので residue
 *   - symlink は本来作られないので residue
 */
function scanStoreResidue(root) {
  const files = [];
  const claims = [];
  const links = [];
  const dirs = [];
  if (!fs.existsSync(root)) return { files, claims, links, dirs, exists: false };

  const walk = (abs) => {
    for (const name of fs.readdirSync(abs)) {
      const p = path.join(abs, name);
      const rel = path.relative(root, p);
      const st = fs.lstatSync(p);
      if (st.isSymbolicLink()) links.push(rel);
      else if (st.isDirectory()) {
        dirs.push(rel);
        if (name.startsWith(".claim-")) claims.push(rel);
        else walk(p);
      } else files.push(rel);
    }
  };
  walk(root);
  return { files, claims, links, dirs, exists: true };
}

const startedAt = Date.now();
try {
  // 上限の根拠が組み込み既定でなく明示 policy であることを、実行時にも固定する。
  // 通常経路では自明に真で、値を書き換えたときに気づくための検査（FI-1 で発火を確認）。
  // 「その上限が実際に効いていた」ことを示すのは canary-busy-refused の側。
  ok("canary-policy-pinned", readJson(POLICY_FILE)?.heavy === HEAVY_LIMIT, `heavy=${HEAVY_LIMIT} を明示 policy で固定`);

  // --- A. 取得と env の受け渡し ---------------------------------------------
  const holderMarker = path.join(MARKERS, "holder.json");
  const releaseMarker = path.join(MARKERS, "release");
  const holder = spawnGoverned({
    label: "canary-holder",
    acquireTimeoutMs: 30_000,
    workloadArgs: ["--marker", holderMarker, "--hold-until", releaseMarker, "--hold-deadline-ms", "20000"],
  });

  const holderReady = await waitForFile(holderMarker, 60_000);
  ok("canary-holder-started", holderReady, holderReady ? "" : "holder の marker が出ない（取得できていない）");

  const observed = holderReady ? readJson(holderMarker) : null;
  ok(
    "canary-child-sees-slot-env",
    !!observed && observed.kind === "heavy" && typeof observed.token === "string" && observed.token.length > 0,
    `kind=${observed?.kind} token=${observed?.token ? "非空" : "空"}`,
  );
  ok(
    "canary-index-within-limit",
    !!observed && Number.isInteger(Number(observed.index)) && Number(observed.index) === 0,
    `index=${observed?.index} (limit=${HEAVY_LIMIT} なので 0 のみ)`,
  );
  // 隔離が実際に効いていること。これを見ないと、CCS_WT_STORE が無視された場合に
  // 「利用者の実 store で動いたのに、空の隔離 store を見て残骸なしと判定する」
  // 偽陰性が成立する（残骸検査が意味を失う）。
  ok(
    "canary-store-isolated",
    fs.existsSync(path.join(STORE_ROOT, "slots", "heavy")),
    `CCS_WT_STORE が効いている: ${STORE_ROOT}`,
  );

  // --- B. 競合時の拒否（短い取得期限で有界化） -------------------------------
  const proberMarker = path.join(MARKERS, "prober.json");
  const prober = spawnGoverned({
    label: "canary-prober",
    acquireTimeoutMs: 300,
    workloadArgs: ["--marker", proberMarker],
  });
  const p = await prober.done;
  ok("canary-busy-refused", p.code === EXIT_RESOURCE_BUSY, `exit=${p.code} (期待 ${EXIT_RESOURCE_BUSY})`);
  // 非ゼロ終了だけでは「拒否された」と言えない。workload が走っていないことまで見る。
  ok("canary-busy-not-executed", !fs.existsSync(proberMarker), "拒否されたなら workload は起動していないはず");
  ok("canary-busy-reason-logged", /RESOURCE_BUSY/.test(p.err), p.err.trim().split("\n").pop() || "(stderr 空)");
  record("canary-prober-wall-ms", `${p.wallMs}  ※記録のみ・合否には使わない`);

  // --- C. 解放 ---------------------------------------------------------------
  fs.writeFileSync(releaseMarker, "release\n");
  const h = await holder.done;
  ok("canary-holder-exit-zero", h.code === 0, `exit=${h.code}`);

  // 「枠が最終的に戻る」ことは stale 回収でも成立する。解放を止めた実装でも
  // 下の canary-released-after-holder は通ってしまう（FI-2 で実測）。
  // したがって finally の解放そのものは、holder 終了**直後**に cell が
  // 消えていることで見る。子の close は release の後に届くので競合しない。
  const holderCell = path.join(STORE_ROOT, "slots", "heavy", `slot-${observed ? observed.index : 0}.json`);
  ok(
    "canary-cell-freed-on-exit",
    !fs.existsSync(holderCell),
    "holder 終了直後に cell が消えている（stale 回収を待たずに解放されている）",
  );

  const afterMarker = path.join(MARKERS, "after.json");
  const after = spawnGoverned({
    label: "canary-after",
    acquireTimeoutMs: 10_000,
    workloadArgs: ["--marker", afterMarker],
  });
  const a = await after.done;
  ok("canary-released-after-holder", a.code === 0, `exit=${a.code}`);
  const afterObs = readJson(afterMarker);
  ok(
    "canary-reacquired-same-index",
    !!afterObs && Number(afterObs.index) === 0,
    `index=${afterObs?.index}（枠が返っていれば同じ index を再取得できる）`,
  );

  // --- D. 残骸なし（隔離 store 配下を再帰走査） ------------------------------
  const residue = scanStoreResidue(STORE_ROOT);
  record("canary-store-tree", `dirs=${residue.dirs.length} files=${residue.files.length} ${JSON.stringify(residue.dirs)}`);
  ok(
    "canary-store-no-residue",
    residue.files.length === 0 && residue.claims.length === 0 && residue.links.length === 0,
    `files=${JSON.stringify(residue.files)} claims=${JSON.stringify(residue.claims)} links=${JSON.stringify(residue.links)}`,
  );

  ok("canary-not-aborted-by-deadline", !abortedByDeadline, `全体 deadline ${GLOBAL_DEADLINE_MS} ms`);
} finally {
  clearTimeout(globalTimer);
  for (const c of alive) {
    try {
      c.kill("SIGKILL");
    } catch {
      /* 既に終了 */
    }
  }
  try {
    // このスイートが作った exact root だけを回収する。
    fs.rmSync(SUITE_ROOT, { recursive: true, force: true });
  } catch {
    /* 下の不存在検査が拾う */
  }
  ok("canary-temp-root-removed", !fs.existsSync(SUITE_ROOT), SUITE_ROOT);
}

console.log("");
record("canary-total-wall-ms", `${Date.now() - startedAt}  ※記録のみ・合否には使わない`);
console.log(`=== wt-canary: ${failed === 0 ? "all cases pass" : `${failed} FAILURES`} ===`);
process.exit(failed ? 1 : 0);
