// =============================================================================
// domain.mjs — executionDomain の判定と domain-local store の解決（ADR-0035 決定 2）
//
// Windows と WSL は lease の置き場所も PID 名前空間も共有しない。`os.tmpdir()` は
// WSL = /tmp、Windows = %LOCALAPPDATA%\Temp で別実体であり、`~` も別実体である
// （/home/<user> と C:\Users\<user>）。したがって「両 domain から見える 1 つの
// store」は存在せず、Phase 1 は domain-local に統一する。
//
// domain の判定に `os.tmpdir()` の値を使わない — 同一 domain 内でも tmpdir は
// 変わりうるため、判定材料としては信頼できない。
// =============================================================================

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export const STORE_VERSION = "wt-v1";

/** WSL かどうかは /proc/version の実体で判定する（環境変数の有無に依存しない）。 */
function isWsl() {
  try {
    return /microsoft/i.test(fs.readFileSync("/proc/version", "utf8"));
  } catch {
    return false;
  }
}

/**
 * executionDomain の識別子。cell に記録され、foreign domain の cell を
 * INDETERMINATE として扱うための材料になる（決定 4 の真理値表 #5）。
 */
export function detectDomain(env = process.env, platform = process.platform) {
  if (platform === "win32") {
    return `win:${env.USERNAME || env.USER || "unknown"}`;
  }
  const uid = typeof process.getuid === "function" ? process.getuid() : "na";
  if (isWsl()) {
    return `wsl:${env.WSL_DISTRO_NAME || "unknown"}:${uid}`;
  }
  return `${platform}:${uid}`;
}

function userHome(env, platform) {
  if (platform === "win32") return env.USERPROFILE || os.homedir();
  return env.HOME || os.homedir();
}

/**
 * domain-local な store のルート。リポジトリにも WT にも紐づけない
 * （同一 domain 上の全プロジェクトが 1 つの枠を共有する）。
 * CCS_WT_STORE は置き場所だけを差し替える（上限には一切関与しない）。
 */
export function storeRoot(env = process.env, platform = process.platform) {
  if (env.CCS_WT_STORE) return env.CCS_WT_STORE;
  if (platform === "win32") {
    const base = env.LOCALAPPDATA || path.join(userHome(env, platform), "AppData", "Local");
    return path.join(base, "ccs", STORE_VERSION);
  }
  const base = env.XDG_STATE_HOME || path.join(userHome(env, platform), ".local", "state");
  return path.join(base, "ccs", STORE_VERSION);
}

/**
 * 上限設定の既定の置き場所。リポジトリの clone / checkout / 取り込みで
 * 書き換わらない位置に置く。これは事故と drift を防ぐためであって、
 * agent が書けない security boundary ではない（ADR-0035 決定 2・既知の限界 3）。
 */
export function policyPath(env = process.env, platform = process.platform) {
  if (env.CCS_WT_POLICY) return env.CCS_WT_POLICY;
  return path.join(userHome(env, platform), ".ccs", "resource-policy.json");
}

export function slotsDir(kind, env = process.env, platform = process.platform) {
  return path.join(storeRoot(env, platform), "slots", kind);
}
