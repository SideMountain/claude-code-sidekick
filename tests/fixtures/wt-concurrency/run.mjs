// =============================================================================
// run.mjs — 並行性 4 ケースの本体（replay.sh から起動される）
//
// 各ケースは専用の一時 store を使い、開発機の実 store・実 WT には触れない。
// 取得・解放の実測時間を最後に報告する。
// =============================================================================

import { spawn } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const REPO = process.argv[2];
const SLOTS = path.join(REPO, ".claude/scripts/wt/slots.mjs");
const { acquire, release, reclaimStale, occupancy, cellPath, STATE, __testing } = await import(pathToFileURL(SLOTS).href);
const releaseClaimForTest = __testing.releaseClaim;
const readClaimForTest = __testing.readClaim;

const DOMAIN = "test:concurrency";
let failed = 0;
const timings = {};

// スイート専用 root。すべての一時領域をこの配下に作り、最後に**この exact root
// だけ**を再帰削除する。ケースごとに散らすと、プロセスが 0 でもファイル資源が
// 実行ごとに増える（実際に増えていた）。
const SUITE_ROOT = path.join(os.tmpdir(), `ccs-wt-suite-${crypto.randomBytes(8).toString("hex")}`);
fs.mkdirSync(SUITE_ROOT, { recursive: true });

function tmpDir(tag) {
  const d = path.join(SUITE_ROOT, `case-${tag}-${crypto.randomBytes(4).toString("hex")}`);
  fs.mkdirSync(path.join(d, ".quarantine"), { recursive: true });
  return d;
}
function ok(name, cond, detail = "") {
  if (cond) console.log(`PASS     ${name}${detail ? "  " + detail : ""}`);
  else {
    console.error(`FAIL     ${name}${detail ? "  " + detail : ""}`);
    failed += 1;
  }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 実プロセス並行の土台。Promise.all で同期関数を呼んでも 1 プロセス内で順に
// 完了するだけで、ADR が要求する「複数プロセスの競合」を証明できない。
// 子プロセスを先に起動し、全員が待ち合わせてから同時に発火させる。
function spawnWorkers({ count, dir, body }) {
  const barrier = path.join(SUITE_ROOT, `barrier-${crypto.randomBytes(6).toString("hex")}`);
  const outDir = path.join(SUITE_ROOT, `out-${crypto.randomBytes(6).toString("hex")}`);
  fs.mkdirSync(outDir, { recursive: true });

  // 子は「開始バリア」で同時発火し、結果を書いたあと「保持バリア」まで slot を
  // 保持し続ける。取得直後に解放すると index の再利用が起きて「同時に何本
  // 保持されているか」を測れない（再利用自体は違反ではなく正常動作）。
  // body は { result, finish } を返す。finish は保持解除時に呼ばれる。
  const script = `
import fs from "node:fs";
const [slotsUrl, dir, barrier, outFile, id] = process.argv.slice(1);
const S = await import(slotsUrl);
// 親は存在確認で読みに来るため、書き込みは tmp → rename で原子的に行う。
// 直接 write すると「存在するが中身が未完成」を読まれる（実際に flaky を観測）。
const atomicWrite = (f, data) => { fs.writeFileSync(f + ".tmp", data); fs.renameSync(f + ".tmp", f); };
atomicWrite(outFile + ".ready", "1");
while (!fs.existsSync(barrier)) {}
const held = await (async () => { ${body} })();
atomicWrite(outFile, JSON.stringify(held.result));
while (!fs.existsSync(barrier + ".release")) {}
if (typeof held.finish === "function") held.finish();
`;

  const children = [];
  for (let i = 0; i < count; i += 1) {
    const outFile = path.join(outDir, `w${i}.json`);
    const proc = spawn(
      process.execPath,
      ["--input-type=module", "-e", script, pathToFileURL(SLOTS).href, dir, barrier, outFile, String(i)],
      { stdio: ["ignore", "ignore", "inherit"] },
    );
    // exit listener は spawn 直後に張る。marker を書いたあとに張ると、先に終了した
    // 子の exit を取り逃がして永久待機になる（このテストが問題にしている
    // 「待機が終わったのに回収されない」を fixture 自身が再現してしまう）。
    let exited = false;
    const exitPromise = new Promise((res) =>
      proc.on("exit", (code, sig) => {
        exited = true;
        res({ code, sig });
      }),
    );
    children.push({ outFile, proc, exitPromise, isExited: () => exited });
  }

  const releaseMarker = () => {
    try {
      fs.writeFileSync(barrier + ".release", "go");
    } catch {
      /* 既に置かれていれば結果は同じ */
    }
  };

  async function settle(deadlineMs = 15000) {
    releaseMarker(); // 何があっても保持は解く
    const timer = sleep(deadlineMs).then(() => "timeout");
    const all = Promise.all(children.map((c) => c.exitPromise)).then(() => "done");
    const who = await Promise.race([all, timer]);
    if (who === "timeout") {
      // このハーネスが起動した PID だけを停止する（他人のプロセスには触らない）。
      for (const c of children) {
        if (!c.isExited()) {
          try {
            c.proc.kill("SIGKILL");
          } catch {
            /* 既に終了 */
          }
        }
      }
      await Promise.race([Promise.all(children.map((c) => c.exitPromise)), sleep(5000)]);
      return false;
    }
    return true;
  }

  return {
    async run(timeoutMs = 60000) {
      try {
        const readyBy = Date.now() + timeoutMs;
        while (children.filter((c) => fs.existsSync(c.outFile + ".ready")).length < count) {
          // 子が ready を書かずに落ちたら即失敗する（待ち続けない）。
          const dead = children.filter((c) => c.isExited() && !fs.existsSync(c.outFile + ".ready"));
          if (dead.length) throw new Error(`worker exited before ready (${dead.length})`);
          if (Date.now() > readyBy) throw new Error("workers did not become ready");
          await sleep(10);
        }
        fs.writeFileSync(barrier, "go"); // 同時発火

        const doneBy = Date.now() + timeoutMs;
        while (children.filter((c) => fs.existsSync(c.outFile)).length < count) {
          const dead = children.filter((c) => c.isExited() && !fs.existsSync(c.outFile));
          if (dead.length) throw new Error(`worker exited before reporting (${dead.length})`);
          if (Date.now() > doneBy) throw new Error("workers did not report");
          await sleep(10);
        }
        // 成功者がまだ保持している状態でスナップショットを取る
        return children.map((c) => {
          try {
            return JSON.parse(fs.readFileSync(c.outFile, "utf8"));
          } catch {
            return { error: "no-output" };
          }
        });
      } finally {
        // 例外で抜けた場合も必ず保持を解き、子を回収する。
        const clean = await settle();
        if (!clean) console.error("WARN     workers did not exit before deadline — killed by fixture");
      }
    },
    releaseSamples() {
      return children
        .map((c) => {
          try {
            return JSON.parse(fs.readFileSync(c.outFile + ".rel", "utf8"));
          } catch {
            return null;
          }
        })
        .filter((x) => x && x.ok && typeof x.releaseNs === "number");
    },
  };
}

// --- 1. 上限 N に N+k 本を同時起動 → 成功数が正確に N -----------------------
// count→create 方式ならここで上限超過が観測される（N+1 本目が成功したら fail）。
async function case1() {
  const N = 3, K = 5;
  const dir = tmpDir("cap");
  const t0 = process.hrtime.bigint();
  const workers = spawnWorkers({
    count: N + K,
    dir,
    body: `
      const t = process.hrtime.bigint();
      const r = S.acquire({ kind: "heavy", limit: ${N}, owner: "w" + id, domain: "${DOMAIN}", dir });
      const acquireNs = Number(process.hrtime.bigint() - t);
      if (!r.ok) return { result: { ok: false, reason: r.reason, scanned: r.scanned, acquireNs } };
      // 保持バリアが落ちるまで slot を持ち続ける
      return {
        result: { ok: true, index: r.index, scanned: r.scanned, acquireNs },
        finish: () => {
          const t2 = process.hrtime.bigint();
          const rel = S.release({ kind: "heavy", index: r.index, token: r.token, dir });
          atomicWrite(outFile + ".rel", JSON.stringify({ ok: rel.ok, releaseNs: Number(process.hrtime.bigint() - t2) }));
        },
      };
    `,
  });
  const results = await workers.run();
  timings.wallMs = Number(process.hrtime.bigint() - t0) / 1e6;

  const won = results.filter((r) => r.ok);
  const acq = results.filter((r) => typeof r.acquireNs === "number").map((r) => r.acquireNs / 1e6);
  const rel = workers.releaseSamples().map((x) => x.releaseNs / 1e6);
  timings.acquireMsAvg = acq.reduce((a, b) => a + b, 0) / Math.max(acq.length, 1);
  timings.releaseMsAvg = rel.reduce((a, b) => a + b, 0) / Math.max(rel.length, 1);

  ok("cap-real-processes", results.every((r) => !r.error), `workers=${results.length}`);
  ok("cap-exact-N", won.length === N, `success=${won.length} want=${N} (N=${N}, processes=${N + K})`);
  ok("cap-unique-index", new Set(won.map((r) => r.index)).size === won.length, `indices=${won.map((r) => r.index).sort()}`);
  ok("cap-scan-bounded", results.every((r) => (r.scanned ?? 0) <= N), `maxScanned=${Math.max(...results.map((r) => r.scanned ?? 0))} limit=${N}`);
  ok("cap-all-released", workers.releaseSamples().length === won.length && occupancy({ kind: "heavy", limit: N, dir }).free === N,
     `releases=${workers.releaseSamples().length} won=${won.length}`);
}

// --- 2. N=1 で回収と取得を競合 → 同時実行数が 1 を超えない -------------------
// quarantine 中の index を空きと見なす実装だと、回収対象が ACTIVE と判明して
// 戻すときに戻し先が埋まり、1 つの index に 2 本が併存する。
//
// 単一プロセスの async だけでは fs 操作が割り込まれず「回収中」の状態が
// 観測点に現れない（実際、素朴な並行ループでは誤実装でも緑になった）。
// そこで **回収の途中状態を明示的に作って**その窓を検査する。
async function case2() {
  const dir = tmpDir("n1");
  const dead = acquire({ kind: "heavy", limit: 1, owner: "dead", domain: DOMAIN, pid: 999_999_999, dir });
  ok("n1-setup", dead.ok);

  // 回収者が rename を終え、まだ検証・削除していない瞬間を再現する。
  const qdir = path.join(dir, ".quarantine");
  const qfile = path.join(qdir, `slot-${dead.index}.midflight`);
  fs.renameSync(cellPath(dir, dead.index), qfile);

  // この窓で取得を試みる。quarantine を占有として数えなければ index が取れてしまう。
  const during = acquire({ kind: "heavy", limit: 1, owner: "racer", domain: DOMAIN, dir });
  ok("n1-quarantine-blocks-acquire", !during.ok && during.reason === "RESOURCE_BUSY",
     `acquired=${during.ok} reason=${during.reason ?? "-"}`);
  if (during.ok) release({ kind: "heavy", index: during.index, token: during.token, dir });

  // 回収対象が ACTIVE と判明した場合の巻き戻し先が空いていること。
  ok("n1-restore-target-free", !fs.existsSync(cellPath(dir, dead.index)));
  fs.renameSync(qfile, cellPath(dir, dead.index)); // 巻き戻し
  ok("n1-restored", fs.existsSync(cellPath(dir, dead.index)));

  // 回収が完了すれば取得できる。
  const rec = reclaimStale({ kind: "heavy", limit: 1, dir, selfDomain: DOMAIN, graceMs: 0 });
  ok("n1-reclaimed-after-window", rec.reclaimed.length === 1);
  const after = acquire({ kind: "heavy", limit: 1, owner: "next", domain: DOMAIN, dir });
  ok("n1-acquirable-after-reclaim", after.ok);
  if (after.ok) release({ kind: "heavy", index: after.index, token: after.token, dir });
  ok("n1-no-quarantine-litter", fs.readdirSync(qdir).length === 0);

  // --- claim の所有権（決定的・回帰 2 に統合） ---
  // claim は「公開の窓」「生存 PID の剥がし」「ABA」を同時に閉じる必要がある。
  const cdir = tmpDir("claim");
  const claimDir = path.join(cdir, ".claim-0");
  const writeClaim = (pid, token, createdAt) => {
    fs.rmSync(claimDir, { recursive: true, force: true });
    fs.mkdirSync(claimDir, { recursive: true });
    fs.writeFileSync(path.join(claimDir, `token-${token}`), JSON.stringify({ pid, token, createdAt }));
  };

  // 生存 PID の claim は、どれだけ古くても剥がされない（時刻だけで剥がさない）
  writeClaim(process.pid, "live-token", 0);
  const blocked = acquire({ kind: "heavy", limit: 1, owner: "x", domain: DOMAIN, dir: cdir, claimGraceMs: 0 });
  ok("claim-alive-pid-not-stolen", !blocked.ok, `acquired=${blocked.ok}`);
  ok("claim-alive-file-intact", fs.existsSync(claimDir));

  // identity が読めない claim は削除せず占有として扱う
  fs.rmSync(claimDir, { recursive: true, force: true });
  fs.mkdirSync(claimDir, { recursive: true });
  fs.writeFileSync(path.join(claimDir, "token-broken"), "{ broken");
  const unknown = acquire({ kind: "heavy", limit: 1, owner: "x", domain: DOMAIN, dir: cdir, claimGraceMs: 0 });
  ok("claim-identity-unknown-occupied", !unknown.ok && fs.existsSync(claimDir),
     `acquired=${unknown.ok} kept=${fs.existsSync(claimDir)}`);

  // 死亡 PID かつ grace 経過なら回収して取得できる
  writeClaim(999_999_997, "dead-token", 0);
  const taken = acquire({ kind: "heavy", limit: 1, owner: "x", domain: DOMAIN, dir: cdir, claimGraceMs: 0 });
  ok("claim-dead-pid-reclaimed", taken.ok, `acquired=${taken.ok}`);
  if (taken.ok) release({ kind: "heavy", index: taken.index, token: taken.token, dir: cdir });

  // 死亡 PID でも grace 内なら剥がさない
  writeClaim(999_999_996, "dead-fresh", Date.now());
  const fresh = acquire({ kind: "heavy", limit: 1, owner: "x", domain: DOMAIN, dir: cdir, claimGraceMs: 60_000 });
  ok("claim-dead-within-grace-kept", !fresh.ok && fs.existsSync(claimDir), `acquired=${fresh.ok}`);

  // ABA の決定的交差試験:
  //   旧 owner が「自分の claim だ」と確認した後、削除に到達する前に claim が
  //   差し替わる、という交差を明示的に作る。旧 owner の解放が新 claim を消せたら
  //   相互排他が壊れている。
  writeClaim(process.pid, "old-owner-token", Date.now());
  const seenByOld = readClaimForTest(cdir, 0); // 旧 owner が「確認」した時点
  ok("aba-old-owner-observed", seenByOld && seenByOld.token === "old-owner-token");
  // ← ここで差し替え（旧 claim が消え、新 owner が公開する）
  fs.rmSync(claimDir, { recursive: true, force: true });
  writeClaim(process.pid, "new-owner-token", Date.now());
  // 旧 owner が確認済みの token で解放を完了しようとする
  const removedByOldToken = releaseClaimForTest(cdir, 0, "old-owner-token");
  const survivor = readClaimForTest(cdir, 0);
  ok("claim-aba-old-token-cannot-release",
     removedByOldToken === false && survivor && survivor.token === "new-owner-token",
     `removed=${removedByOldToken} survivor=${survivor && survivor.token}`);
  ok("claim-token-match-releases",
     releaseClaimForTest(cdir, 0, "new-owner-token") === true && !fs.existsSync(claimDir));

  // --- slot 本体の ABA（決定的交差）---
  // 「旧 cell を確認済みの P2 が、差し替え後に unlink する」交差を再現する。
  // P1 の解放完了後に旧 token を渡すだけでは、旧実装でも新 cell の再読で
  // NOT_OWNER になり通ってしまう。**claim を別 owner が保持したまま release を
  // 呼ぶ**ことで、claim 境界を持たない実装が決定的に赤くなる。
  const rdir = tmpDir("release-aba");
  const first = acquire({ kind: "heavy", limit: 1, owner: "p1", domain: DOMAIN, dir: rdir });
  ok("release-aba-setup", first.ok);

  // 別 owner が index を claim 中（生存 PID・grace 内なので剥がせない）
  const otherClaimDir = path.join(rdir, `.claim-${first.index}`);
  fs.mkdirSync(otherClaimDir, { recursive: true });
  fs.writeFileSync(
    path.join(otherClaimDir, "token-other-owner"),
    JSON.stringify({ pid: process.pid, token: "other-owner", createdAt: Date.now() }),
  );

  const claimedRelease = release({ kind: "heavy", index: first.index, token: first.token, dir: rdir });
  ok("release-aba-blocked-by-claim",
     !claimedRelease.ok && String(claimedRelease.reason).startsWith("CLAIM_UNAVAILABLE:"),
     `reason=${claimedRelease.reason}`);
  ok("release-aba-cell-survives-while-claimed", fs.existsSync(cellPath(rdir, first.index)));

  // claim を正しい token で解放すれば、通常どおり解放できる
  ok("release-aba-claim-released", releaseClaimForTest(rdir, first.index, "other-owner") === true);
  const freed = release({ kind: "heavy", index: first.index, token: first.token, dir: rdir });
  ok("release-aba-release-after-claim-freed", freed.ok, `reason=${freed.reason}`);
  ok("release-aba-cell-gone", !fs.existsSync(cellPath(rdir, first.index)));

  // 旧 token では解放できない（差し替え後の新 owner の cell を消さない）
  const second = acquire({ kind: "heavy", limit: 1, owner: "new-owner", domain: DOMAIN, dir: rdir });
  ok("release-aba-reacquired", second.ok && second.token !== first.token);
  const late = release({ kind: "heavy", index: second.index, token: first.token, dir: rdir });
  ok("release-aba-old-token-rejected", !late.ok && late.reason === "NOT_OWNER", `reason=${late.reason}`);
  ok("release-aba-new-cell-survives", fs.existsSync(cellPath(rdir, second.index)));
  ok("release-aba-new-owner-can-release",
     release({ kind: "heavy", index: second.index, token: second.token, dir: rdir }).ok &&
       !fs.existsSync(cellPath(rdir, second.index)));
}

// --- 3. 同一 stale cell への同時回収 → rename 成功は 1 つだけ ---------------
async function case3() {
  const dir = tmpDir("reclaim");
  const dead = acquire({ kind: "heavy", limit: 2, owner: "dead", domain: DOMAIN, pid: 999_999_998, dir });
  ok("reclaim-setup", dead.ok);

  const workers = spawnWorkers({
    count: 6,
    dir,
    body: `
      const r = S.reclaimStale({ kind: "heavy", limit: 2, dir, selfDomain: "${DOMAIN}", graceMs: 0 });
      return { result: { reclaimed: r.reclaimed.length, scanned: r.scanned } };
    `,
  });
  const runs = await workers.run();
  ok("reclaim-real-processes", runs.every((r) => !r.error), `workers=${runs.length}`);
  const total = runs.reduce((a, r) => a + (r.reclaimed ?? 0), 0);
  ok("reclaim-once-only", total === 1, `reclaimed=${total} want=1 (processes=${runs.length})`);
  ok("reclaim-cell-gone", !fs.existsSync(cellPath(dir, dead.index)));
  ok("reclaim-scan-bounded", runs.every((r) => (r.scanned ?? 0) <= 2), `maxScanned=${Math.max(...runs.map((r) => r.scanned ?? 0))}`);

  // ACTIVE な cell は回収されず、元の名前へ戻る（誤回収の巻き戻し）
  const live = acquire({ kind: "heavy", limit: 2, owner: "live", domain: DOMAIN, pid: process.pid, dir });
  const r2 = reclaimStale({ kind: "heavy", limit: 2, dir, selfDomain: DOMAIN, graceMs: 0 });
  // 正常時は ok:true（配列だけでなく真偽で伝わること）
  ok("reclaim-ok-flag-true", r2.ok === true && r2.claimReleaseFailures.length === 0,
     `ok=${r2.ok} failures=${r2.claimReleaseFailures.length}`);
  ok("reclaim-keeps-active",
    r2.reclaimed.length === 0 && fs.existsSync(cellPath(dir, live.index)) &&
      r2.kept.some((k) => k.state === STATE.ACTIVE),
    `kept=${JSON.stringify(r2.kept.map((k) => k.state))}`);
  release({ kind: "heavy", index: live.index, token: live.token, dir });
}

// --- 4. SIGKILL 後に stale recovery で枠が戻る ------------------------------
// finally が走らない経路。実プロセスを起こして SIGKILL する。
async function case4() {
  const dir = tmpDir("kill");
  const child = spawn(process.execPath, ["-e", "setTimeout(()=>{},60000)"], { stdio: "ignore" });
  await sleep(150);
  const got = acquire({ kind: "heavy", limit: 1, owner: "child", domain: DOMAIN, pid: child.pid, dir });
  ok("kill-setup", got.ok && occupancy({ kind: "heavy", limit: 1, dir }).free === 0);

  // 生きている間は回収されない
  const before = reclaimStale({ kind: "heavy", limit: 1, dir, selfDomain: DOMAIN, graceMs: 0 });
  ok("kill-alive-not-reclaimed", before.reclaimed.length === 0, `kept=${JSON.stringify(before.kept.map((k) => k.state))}`);

  child.kill("SIGKILL");
  await new Promise((r) => child.on("exit", r));
  await sleep(100);

  const after = reclaimStale({ kind: "heavy", limit: 1, dir, selfDomain: DOMAIN, graceMs: 0 });
  ok("kill-reclaimed-after-death", after.reclaimed.length === 1, `reclaimed=${after.reclaimed.length}`);
  ok("kill-slot-free", occupancy({ kind: "heavy", limit: 1, dir }).free === 1);
  const re = acquire({ kind: "heavy", limit: 1, owner: "next", domain: DOMAIN, dir });
  ok("kill-reacquirable", re.ok);
  if (re.ok) release({ kind: "heavy", index: re.index, token: re.token, dir });
}

const started = Date.now();
try {
  await case1();
  await case2();
  await case3();
  await case4();
} finally {
  // 例外で抜けた場合も、このスイートが作った exact root だけを回収する。
  try {
    fs.rmSync(SUITE_ROOT, { recursive: true, force: true });
  } catch {
    /* 下の不存在検査が拾う */
  }
  ok("suite-temp-root-removed", !fs.existsSync(SUITE_ROOT), SUITE_ROOT);
}
const elapsed = (Date.now() - started) / 1000;

console.log("");
console.log(`  実測: acquire 平均 ${timings.acquireMsAvg.toFixed(3)} ms / release 平均 ${timings.releaseMsAvg.toFixed(3)} ms`);
console.log(`  合計 wall: ${elapsed.toFixed(2)} 秒`);
console.log(`=== wt-concurrency: ${failed === 0 ? "all cases pass" : `${failed} FAILURES`} ===`);
process.exit(failed ? 1 : 0);
