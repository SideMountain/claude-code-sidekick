// =============================================================================
// slots.mjs — 固定 cell による同時実行数の統治（ADR-0035 決定 3・決定 4）
//
// 上限 N から固定 cell slot-0 … slot-(N-1) を導出し、O_EXCL による作成の成否
// そのものを排他とする。一意 token を作ってから占有数を数える方式は、count と
// create の間の競合で上限を破る（2 プロセスが同時に「N-1 本」と数えて両方成功
// する）。数えてから作る限りこの窓は消せない。
//
// index の占有判定は cell の存在だけでは足りない。回収途中（quarantine 中）の
// index を空きと見なすと、回収対象が ACTIVE と判明して戻すときに戻し先が
// 埋まっており、その瞬間 1 つの index に 2 本が併存する。
//
// 走査量は **設定された slot 上限 N にのみ比例**する。全 WT・全プロセスを
// 走査しない（ADR-0035 Phase 3 受入条件）。
// =============================================================================

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { slotsDir } from "./domain.mjs";

export const CELL_VERSION = 1;
export const DEFAULT_TTL_MS = 8 * 60 * 60 * 1000;
export const DEFAULT_GRACE_MS = 10_000;
export const QUARANTINE_DIR = ".quarantine";
// claim の回収条件は「PID 死亡 かつ この時間が経過」。TTL 単独では剥がさない。
export const DEFAULT_CLAIM_GRACE_MS = 10_000;

export const STATE = Object.freeze({
  ACTIVE: "ACTIVE",
  ACTIVE_EXPIRED: "ACTIVE_EXPIRED",
  STALE: "STALE",
  INDETERMINATE: "INDETERMINATE",
});

export function hashToken(token) {
  return crypto.createHash("sha256").update(String(token)).digest("hex");
}

export function cellPath(dir, index) {
  return path.join(dir, `slot-${index}.json`);
}

// ---------------------------------------------------------------------------
// index 単位の reclaim claim（BLOCKER 3 / claim 所有権）
//
// acquire は「cell を作る → 内容を書く → 公開完了」の間に窓を持つ。この窓で
// reclaimer が cell を quarantine へ rename すると、acquire 撤退後に reclaimer が
// ACTIVE / INDETERMINATE と判定して元へ戻し、**token を受け取った owner が誰も
// いない占有 cell** が残る。そこで index ごとに claim を置き、公開と回収を
// 相互排他にする。
//
// claim 自体も同じ競合クラスを持つため、次の 3 つを守る:
//   1. **公開は mkdir の排他性だけを根拠にする** — ディレクトリの rename は
//      プロセス間競合で EPERM を返し、宛先の存在確認と不可分にできない（実測）
//   2. **identity 不明は削除せず占有として扱う** — 読めない claim を剥がす経路を
//      持たない（読めないこと自体は、誰も持っていないことの証明にならない）
//   3. **回収は PID 死亡かつ grace 経過のときだけ** — 生存 PID を経過時間だけで
//      剥がさない（PC の停止・高負荷・デバッガ停止で相互排他が破れる）
//   4. **解放は非空 token の完全一致時だけ** — 一致を見ないと、ABA（別 owner が
//      作り直した claim）を古い owner が消せる
// ---------------------------------------------------------------------------
// Windows では、他プロセスが同名を作成中／削除中のとき排他作成が EEXIST ではなく
// EPERM / EACCES / EBUSY を返すことがある（実プロセス並行テストで観測）。ただし
// これらは本物の権限エラーでも起きるため、**対象が存在しないなら競合ではない**と
// 判定して fail-loud にする（競合扱いすると権限エラーのまま既定 30 分待つ）。
function isContendedCreate(e, targetPath) {
  if (!e) return false;
  if (e.code === "EEXIST") return true;
  if (["EPERM", "EACCES", "EBUSY"].includes(e.code)) return fs.existsSync(targetPath);
  return false;
}

// claim は **token 子ファイルを持つディレクトリ** として公開する。
//
// 「token を読んで一致を確認 → 固定パスを unlink」は不可分ではない。確認と削除の
// 間に旧 claim が消えて新 claim が公開されると、**古い所有者が新 owner の claim を
// 削除できる**（ABA）。ディレクトリ方式ならこの経路が構造的に存在しない:
//   - 公開 = mkdir（宛先が在れば EEXIST）+ token 子の書き込み
//   - 解放 = **自分の token 子を unlink できたときだけ** rmdir する。新 claim へ
//     差し替わっていれば自分の token 子は存在せず（ENOENT）、rmdir に到達しない
//   - rmdir は空のときしか成功しない（他 owner の token 子があれば ENOTEMPTY）
//
// 公開は mkdir → token 子の書き込みの 2 段なので、**空の claim は「公開の途中」でも
// 「解放の途中」でも生じる**。どちらも所有者を名乗れないため占有として扱い、
// grace 経過後にだけ片付ける（publish 中の一瞬を stale と誤認しないため）。
function claimPath(dir, index) {
  return path.join(dir, `.claim-${index}`);
}

function tokenChild(dir, index, token) {
  return path.join(claimPath(dir, index), `token-${token}`);
}

/** claim ディレクトリの identity を読む。読めない・空は null（＝占有だが不明）。 */
function readClaim(dir, index) {
  const cdir = claimPath(dir, index);
  let names;
  try {
    names = fs.readdirSync(cdir);
  } catch {
    return null;
  }
  const child = names.find((n) => n.startsWith("token-"));
  if (!child) return { empty: true, token: null, pid: null, createdAt: null };
  try {
    const c = JSON.parse(fs.readFileSync(path.join(cdir, child), "utf8"));
    if (!c || typeof c !== "object") return null;
    if (!Number.isInteger(c.pid) || typeof c.token !== "string" || !c.token) return null;
    if (!Number.isInteger(c.createdAt)) return null;
    return { empty: false, ...c };
  } catch {
    return null;
  }
}

/** claim の識別子（呼び出し単位で 1 token）。 */
function makeClaimToken() {
  return crypto.randomBytes(16).toString("hex");
}

const CLAIM_TRANSIENT_RETRIES = 6;

// 同期の短い待機。競合の窓が閉じるのを待つためだけに使う。
function sleepSyncMs(ms) {
  try {
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
  } catch {
    const end = Date.now() + ms;
    while (Date.now() < end) { /* SharedArrayBuffer 不可な環境の保険 */ }
  }
}

/**
 * claim を publish する。**mkdir が排他かつ原子的**であることを唯一の根拠にする
 * （ディレクトリの rename はプロセス間競合で EPERM を返すことがあり、宛先の
 * 存在確認と不可分にできないため publish の手段にしない — 実測で確認）。
 *
 * mkdir 直後は token 子がまだ無い「空の claim」になる。空は **占有（identity 不明）**
 * として扱い、削除しない。空のまま残るのは publish 途中か解放途中でクラッシュした
 * 場合だけなので、その回収は grace 経過後にのみ行う。
 *
 * @returns {{ok:true} | {ok:false, reason:string}}
 */
function tryClaim(dir, index, { nowMs, isAlive, graceMs, token }) {
  const target = claimPath(dir, index);
  let transient = 0;
  for (let attempt = 0; attempt < 2 + CLAIM_TRANSIENT_RETRIES; attempt += 1) {
    try {
      fs.mkdirSync(target); // 宛先が在れば EEXIST = 排他かつ原子的
      fs.writeFileSync(
        path.join(target, `token-${token}`),
        JSON.stringify({ pid: process.pid, token, createdAt: nowMs }),
      );
      return { ok: true };
    } catch (e) {
      if (["EPERM", "EACCES", "EBUSY"].includes(e.code) && !fs.existsSync(target)) {
        // 別プロセスが同じ宛先を作成・削除している最中に出る。existsSync は
        // mkdir と不可分ではないので「不在」だけで権限エラーと断定しない。
        transient += 1;
        if (transient <= CLAIM_TRANSIENT_RETRIES) {
          sleepSyncMs(Math.min(2 * transient, 20));
          continue;
        }
        // 予算超過時は、親が書けるかという正の検査で本物の権限エラーと判別する。
        if (!isWritableDir(dir)) throw e;
        return { ok: false, reason: "claim-contended" };
      }
      if (e.code !== "EEXIST") throw e;

      const held = readClaim(dir, index);
      if (held === null) {
        return { ok: false, reason: "claim-identity-unknown" }; // 破損。削除しない
      }
      if (held.empty) {
        // 公開途中 or 解放途中。どちらも grace 経過後にだけ片付ける。
        if (nowMs - dirCreatedAt(target) >= graceMs) {
          try {
            fs.rmdirSync(target);
          } catch {
            /* 他プロセスが先に片付けた / 途中で token 子が入った */
          }
          continue;
        }
        return { ok: false, reason: "claim-empty-within-grace" };
      }
      if (held.token === token) return { ok: true };
      const dead = !isAlive(held.pid);
      const aged = nowMs - held.createdAt >= graceMs;
      if (dead && aged) {
        releaseClaim(dir, index, held.token);
        continue;
      }
      return { ok: false, reason: dead ? "claim-dead-within-grace" : "claim-held" };
    }
  }
  return { ok: false, reason: "claim-contended" };
}

function dirCreatedAt(p) {
  try {
    return fs.statSync(p).mtimeMs;
  } catch {
    return 0;
  }
}

/**
 * 解放は「自分の token 子を消せたときだけ rmdir」。
 * 新 claim へ差し替わっていれば自分の token 子は無く（ENOENT）、rmdir に到達しない。
 */
function releaseClaim(dir, index, token) {
  if (typeof token !== "string" || !token) return false;
  try {
    fs.unlinkSync(tokenChild(dir, index, token));
  } catch {
    return false; // 自分の token 子が無い = もう自分の claim ではない
  }
  try {
    fs.rmdirSync(claimPath(dir, index)); // 空のときしか成功しない
  } catch {
    /* 他 owner の子が入っていれば ENOTEMPTY。触らない */
  }
  // **消滅まで確認して返す。** ここを真偽で返さないと、claim が残ったまま
  // 公開 API が成功を返し、index が誰にも取れない状態が緑になる。
  return !fs.existsSync(claimPath(dir, index));
}

function quarantineDirOf(dir) {
  return path.join(dir, QUARANTINE_DIR);
}

/** index i に対する quarantine が 1 件でもあるか。走査は当該 index のみ。 */
function quarantineExists(dir, index) {
  let names;
  try {
    names = fs.readdirSync(quarantineDirOf(dir));
  } catch {
    return false;
  }
  const prefix = `slot-${index}.`;
  return names.some((n) => n.startsWith(prefix));
}

// ---------------------------------------------------------------------------
// 真理値表（決定 4）— 純粋関数。I/O を持たないので fixture で網羅できる。
//
//  # | leaseUntil | pid    | domain          | state           | 回収
//  1 | 未来       | 生存   | 同一            | ACTIVE          | 不可
//  2 | 未来       | 死亡   | 同一            | STALE           | 可（grace 経過後）
//  3 | 過去       | 生存   | 同一            | ACTIVE_EXPIRED  | 不可
//  4 | 過去       | 死亡   | 同一            | STALE           | 可
//  5 | 任意       | 判定不能 | foreign domain | INDETERMINATE   | 不可
//  6 | 解析不能   | —      | —               | INDETERMINATE   | 不可
//
// #3「期限切れ + PID 生存」を回収しないのは、生きているプロセスの枠を回収すると
// 二重割り当てになり、期限更新漏れというバグを資源枯渇に変換するため。
// 判定は cell 自身の属性だけで行い、待ち手の経過時間は材料にしない。
// ---------------------------------------------------------------------------
export function classifyCell({ cell, nowMs, selfDomain, pidAlive, graceMs = DEFAULT_GRACE_MS }) {
  const bad = (reason) => ({ state: STATE.INDETERMINATE, reclaimable: false, reason });

  if (!cell || typeof cell !== "object") return bad("unparsable");
  for (const k of ["v", "kind", "owner", "executionDomain", "pid", "createdAt", "leaseUntil"]) {
    if (cell[k] === undefined || cell[k] === null) return bad(`missing:${k}`);
  }
  if (cell.executionDomain !== selfDomain) return bad("foreign-domain");

  const until = Date.parse(cell.leaseUntil);
  const created = Date.parse(cell.createdAt);
  if (Number.isNaN(until) || Number.isNaN(created)) return bad("unparsable-time");

  // PID の生死を確認できないものを、死亡側（回収可）へ倒さない。
  if (pidAlive === null || pidAlive === undefined) return bad("pid-unknown");

  if (pidAlive) {
    return until > nowMs
      ? { state: STATE.ACTIVE, reclaimable: false, reason: "alive-within-lease" }
      : { state: STATE.ACTIVE_EXPIRED, reclaimable: false, reason: "alive-lease-expired" };
  }
  // 取得直後で内容がまだ書かれていない cell を stale と誤認しない。
  const withinGrace = nowMs - created < graceMs;
  return {
    state: STATE.STALE,
    reclaimable: !withinGrace,
    reason: withinGrace ? "dead-within-grace" : "dead",
  };
}

export function isProcessAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    // EPERM は「他ユーザーのプロセスとして生存」を意味する。
    return e && e.code === "EPERM";
  }
}

function readCell(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// 取得（決定 3）
//   1. quarantine-slot-<i>-* があれば i を飛ばす（回収中の index は取らない）
//   2. slot-<i>.json を O_EXCL で作成。EEXIST なら i を飛ばす
//   3. 作成に成功したら quarantine を再確認する。1 と 2 の間に他プロセスが
//      quarantine へ rename していた場合、後から入った自分が退く
// ---------------------------------------------------------------------------
export function acquire({
  kind,
  limit,
  owner,
  domain,
  pid = process.pid,
  label = "",
  ttlMs = DEFAULT_TTL_MS,
  nowMs = Date.now(),
  claimGraceMs = DEFAULT_CLAIM_GRACE_MS,
  isAlive = isProcessAlive,
  dir,
  env = process.env,
  platform = process.platform,
}) {
  const target = dir || slotsDir(kind, env, platform);
  fs.mkdirSync(quarantineDirOf(target), { recursive: true });

  let scanned = 0;
  for (let i = 0; i < limit; i += 1) {
    scanned += 1;

    // 回収中の index は取らない。claim を取れた間は reclaimer が rename できないので、
    // 公開の途中で cell を持ち去られることがない。
    const claimToken = makeClaimToken();
    const claim = tryClaim(target, i, { nowMs, isAlive, graceMs: claimGraceMs, token: claimToken });
    if (!claim.ok) continue;

    let published = null;
    let skipIndex = false; // この index を諦める（try 内で continue しない）
    let claimReleased = false;
    try {
      // 回収者がクラッシュして quarantine だけ残っている index は占有として扱う。
      if (quarantineExists(target, i)) {
        skipIndex = true;
      } else {
        const token = crypto.randomBytes(32).toString("hex");
        const cell = {
          v: CELL_VERSION,
          kind,
          owner,
          executionDomain: domain,
          pid,
          label,
          releaseTokenHash: hashToken(token),
          createdAt: new Date(nowMs).toISOString(),
          leaseUntil: new Date(nowMs + ttlMs).toISOString(),
        };
        const file = cellPath(target, i);
        let fd = null;
        try {
          fd = fs.openSync(file, "wx"); // O_CREAT | O_EXCL — 作成の成否そのものが排他
        } catch (e) {
          if (isContendedCreate(e, file)) skipIndex = true; // 他者が作成中／削除中
          else throw e;
        }
        if (fd !== null) {
          try {
            fs.writeSync(fd, JSON.stringify(cell));
          } finally {
            fs.closeSync(fd);
          }
          published = { ok: true, index: i, token, cell, scanned };
        }
      }
    } finally {
      // claim は公開が終わってから外す。外した時点で cell は完全な内容を持つ。
      claimReleased = releaseClaim(target, i, claimToken);
    }

    // **claim 解放の成否を最優先で判定する。** try 内で continue すると、
    // quarantine 分岐・cell 競合分岐で claim が残ったまま別 index の成功を返せる。
    if (!claimReleased) {
      if (published) {
        // 巻き戻しは **自分が owner だと確認できたときだけ**行う。claim 解放失敗は
        // 所有権状態が崩れている場面なので、固定パスの無条件 unlink はしない。
        const current = readCell(cellPath(target, i));
        if (current && current.releaseTokenHash === hashToken(published.token)) {
          try {
            fs.unlinkSync(cellPath(target, i));
          } catch {
            /* 既に無ければ結果は同じ */
          }
        } else {
          return {
            ok: false,
            reason: "CLAIM_RELEASE_FAILED",
            detail: current === null ? "cell-unreadable" : "cell-not-owned",
            index: i,
            scanned,
          };
        }
      }
      return { ok: false, reason: "CLAIM_RELEASE_FAILED", index: i, scanned };
    }

    if (published) return published;
    if (skipIndex) continue;
  }
  return { ok: false, reason: "RESOURCE_BUSY", scanned };
}

// ---------------------------------------------------------------------------
// 通常解放（決定 5）— 自分の cell だけ。秘密 token が一致したときのみ。
// session ID や worktree key は診断・検索用のキーであって解放権限ではない。
// ---------------------------------------------------------------------------
export function release({
  kind,
  index,
  token,
  dir,
  nowMs = Date.now(),
  claimGraceMs = DEFAULT_CLAIM_GRACE_MS,
  isAlive = isProcessAlive,
  env = process.env,
  platform = process.platform,
}) {
  const target = dir || slotsDir(kind, env, platform);
  const file = cellPath(target, index);

  // 「cell を読んで token 一致 → unlink」は不可分ではない。二重解放した P1/P2 が
  // 旧 cell を読み、P1 の削除後に新 owner が同じ index を取得すると、P2 の unlink が
  // **新 owner の cell を消す**（ABA）。acquire / reclaim と同じ排他境界に入れ、
  // claim 保持中に「再読 → 照合 → unlink」まで完了させる。
  const claimToken = makeClaimToken();
  const claim = tryClaim(target, index, {
    nowMs,
    isAlive,
    graceMs: claimGraceMs,
    token: claimToken,
  });
  if (!claim.ok) {
    // claim を取れないことを成功に合流させない。呼び出し側の解放失敗経路へ返す。
    return { ok: false, reason: `CLAIM_UNAVAILABLE:${claim.reason}` };
  }

  let outcome = null;
  try {
    if (!fs.existsSync(file)) {
      // 既に無い。解放は冪等（二重解放を失敗にしない）。
      outcome = { ok: true, reason: "absent" };
      return outcome;
    }
    // claim 保持中に読み直す。ここから unlink までの間に他者は publish できない。
    const cell = readCell(file);
    if (cell === null) {
      // 存在するのに読めない = 占有 cell が残ったまま「解放できたか分からない」状態。
      // 成功に合流させると、コマンド成功の裏で枠が埋まったまま緑になる。
      return { ok: false, reason: "UNREADABLE" };
    }
    if (!token || cell.releaseTokenHash !== hashToken(token)) {
      return { ok: false, reason: "NOT_OWNER" };
    }
    try {
      fs.unlinkSync(file);
    } catch (e) {
      if (!e || e.code !== "ENOENT") return { ok: false, reason: "UNLINK_FAILED" };
    }
    outcome = { ok: true, reason: "released" };
    return outcome;
  } finally {
    if (!releaseClaim(target, index, claimToken) && outcome && outcome.ok) {
      // cell は消せたが claim が残っている = index が誰にも取れない。
      // ここを成功で返すと、枠が 1 本死んだまま呼び出し側が緑になる。
      outcome.ok = false;
      outcome.reason = "CLAIM_RELEASE_FAILED";
    }
  }
}

// ---------------------------------------------------------------------------
// stale 回収（決定 3）— quarantine への atomic rename を先行させる。
// 「検証してから消す」順序だと、2 プロセスが同じ cell を STALE と判定して両方が
// 回収し、両方が取り直して上限を超える。rename に成功した 1 プロセスだけが
// 回収者になる。確定は必ず rename 後の再検証で行う。
// ---------------------------------------------------------------------------
export function reclaimStale({
  kind,
  limit,
  dir,
  selfDomain,
  nowMs = Date.now(),
  graceMs = DEFAULT_GRACE_MS,
  claimGraceMs = DEFAULT_CLAIM_GRACE_MS,
  isAlive = isProcessAlive,
  env = process.env,
  platform = process.platform,
}) {
  const target = dir || slotsDir(kind, env, platform);
  const qdir = quarantineDirOf(target);
  fs.mkdirSync(qdir, { recursive: true });
  const claimToken = makeClaimToken();

  const reclaimed = [];
  const kept = [];
  const claimReleaseFailures = [];
  let scanned = 0;

  for (let i = 0; i < limit; i += 1) {
    scanned += 1;

    // 公開中の index には触れない。claim を取れた間は acquire が cell を作らないので、
    // 「公開途中の cell を持ち去って owner 不在で復元する」競合が起きない。
    const claim = tryClaim(target, i, { nowMs, isAlive, graceMs: claimGraceMs, token: claimToken });
    if (!claim.ok) continue;

    try {
      // 前の回収者がクラッシュして残した quarantine を先に引き取る。
      const leftovers = fs
        .readdirSync(qdir)
        .filter((n) => n.startsWith(`slot-${i}.`))
        .map((n) => path.join(qdir, n));

      const targets = leftovers.slice();
      if (fs.existsSync(cellPath(target, i))) {
        const qfile = path.join(qdir, `slot-${i}.${crypto.randomBytes(8).toString("hex")}`);
        try {
          fs.renameSync(cellPath(target, i), qfile); // atomic
          targets.push(qfile);
        } catch {
          /* 既に消えた */
        }
      }

      for (const qfile of targets) {
        // 確定は必ず rename 後の再読で行う（rename 前の判定を根拠にしない）。
        const cell = readCell(qfile);
        const verdict = classifyCell({
          cell,
          nowMs,
          selfDomain,
          pidAlive: cell && Number.isInteger(cell.pid) ? isAlive(cell.pid) : null,
          graceMs,
        });

        if (verdict.state === STATE.STALE && verdict.reclaimable) {
          try {
            fs.unlinkSync(qfile);
          } catch {
            /* 消えていれば結果は同じ */
          }
          reclaimed.push({ index: i, ...verdict });
        } else if (!fs.existsSync(cellPath(target, i))) {
          // 誤回収の巻き戻し。claim を保持しているので戻し先は空いている。
          fs.renameSync(qfile, cellPath(target, i));
          kept.push({ index: i, ...verdict });
        } else {
          // 復元先が既に埋まっている（正常運用では起きない）。
          // 消して枠を空けると、生きた owner の枠を奪う可能性があるため残して報告する。
          kept.push({ index: i, ...verdict, note: "left-in-quarantine" });
        }
      }
    } finally {
      if (!releaseClaim(target, i, claimToken)) {
        // claim が残った index は以後取得できない。silent に落とさず結果へ載せる。
        claimReleaseFailures.push({ index: i, reason: "CLAIM_RELEASE_FAILED" });
      }
    }
  }
  // 配列だけだと呼び出し側が成功として扱いやすい。ok を明示して伝える。
  return { ok: claimReleaseFailures.length === 0, reclaimed, kept, scanned, claimReleaseFailures };
}

// 非公開契約: 回帰テスト専用の口。製品コードから呼ばない。
// claim の所有権契約（自分の token 子を消せたときだけ rmdir・ABA 拒否）は
// 内部関数でしか観測できないため、ここだけを開けている。
export const __testing = Object.freeze({ releaseClaim, readClaim });

/** 診断用。占有中の index を返す（cell か quarantine のどちらかがあれば占有）。 */
export function occupancy({ kind, limit, dir, env = process.env, platform = process.platform }) {
  const target = dir || slotsDir(kind, env, platform);
  const busy = [];
  for (let i = 0; i < limit; i += 1) {
    if (fs.existsSync(cellPath(target, i)) || quarantineExists(target, i)) busy.push(i);
  }
  return { busy, free: limit - busy.length, scanned: limit };
}
