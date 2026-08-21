// =============================================================================
// policy.mjs — 上限の解決（ADR-0035 決定 2）
//
// 合成は min(policy, repo, env) の一方向。repo / env は**下げることしかできない**。
// これは defense-in-depth（うっかり repo 設定で枠が広がる事故の防止）であって、
// 改変不能性の主張ではない。
//
// 「未設定」と「壊れている」を区別する:
//   不在   → 組み込み既定（heavy 1 / runtime 2）。未設定は正常な初期状態であり、
//            ここを 1 に倒すと通常運用が常時縮退する。
//   壊れている → heavy 1 / runtime 1。「読めなかった」を「上限なし」にも
//            「組み込み既定」にも合流させない。
// =============================================================================

import fs from "node:fs";
import { policyPath } from "./domain.mjs";

export const KINDS = ["heavy", "runtime"];
export const BUILTIN_DEFAULT = Object.freeze({ heavy: 1, runtime: 2 });
export const SAFE_FALLBACK = Object.freeze({ heavy: 1, runtime: 1 });

/** 正の整数だけを上限として受け付ける（0 以下・非数値・小数は不正）。 */
function isPositiveInt(v) {
  return typeof v === "number" && Number.isInteger(v) && v > 0;
}

/**
 * 下げる方向にだけ効く上書き値を取り出す。
 * 不正な値は**無視する**（無視しても base 以下のままなので枠は広がらない）。
 */
function lowerOnly(base, override) {
  const out = { ...base };
  for (const k of KINDS) {
    const v = override?.[k];
    if (isPositiveInt(v) && v < out[k]) out[k] = v;
  }
  return out;
}

/**
 * 純粋関数。I/O を持たないので fixture で網羅できる。
 * @param policyText  policy ファイルの中身。**不在は null**（空文字列は「壊れている」）
 * @param repoValues  リポジトリ内設定（下げる方向のみ）
 * @param envValues   環境変数由来（下げる方向のみ）
 * @returns {{heavy:number, runtime:number, base:"builtin"|"policy"|"safe", reason:string}}
 */
export function resolveLimits({ policyText = null, repoValues = null, envValues = null } = {}) {
  let base;
  let baseKind;
  let reason;

  if (policyText === null || policyText === undefined) {
    base = { ...BUILTIN_DEFAULT };
    baseKind = "builtin";
    reason = "policy-absent";
  } else {
    let parsed = null;
    try {
      parsed = JSON.parse(policyText);
    } catch {
      parsed = null;
    }
    const usable =
      parsed !== null &&
      typeof parsed === "object" &&
      !Array.isArray(parsed) &&
      // 存在するキーはすべて正の整数でなければならない。1 つでも不正なら
      // ファイル全体を「壊れている」として扱う（部分採用で意図を推測しない）。
      KINDS.every((k) => parsed[k] === undefined || isPositiveInt(parsed[k]));

    if (!usable) {
      base = { ...SAFE_FALLBACK };
      baseKind = "safe";
      reason = "policy-unreadable";
    } else {
      base = { ...BUILTIN_DEFAULT };
      for (const k of KINDS) if (isPositiveInt(parsed[k])) base[k] = parsed[k];
      baseKind = "policy";
      reason = "policy-ok";
    }
  }

  const limits = lowerOnly(lowerOnly(base, repoValues), envValues);
  return { ...limits, base: baseKind, reason };
}

/** 環境変数からの上書き（下げる方向のみ）。数値以外は無視される。 */
export function envOverrides(env = process.env) {
  const num = (s) => (s === undefined ? undefined : Number(s));
  return { heavy: num(env.CCS_WT_HEAVY_MAX), runtime: num(env.CCS_WT_RUNTIME_MAX) };
}

/** 実ファイルを読んで解決する。不在（ENOENT）だけが「未設定」で、他の失敗は「壊れている」。 */
export function loadLimits(env = process.env, platform = process.platform, repoValues = null) {
  const p = policyPath(env, platform);
  let policyText = null;
  try {
    policyText = fs.readFileSync(p, "utf8");
  } catch (e) {
    // ENOENT 以外（権限・IO エラー）は「読めなかった」であり、未設定ではない。
    policyText = e && e.code === "ENOENT" ? null : "";
  }
  return resolveLimits({ policyText, repoValues, envValues: envOverrides(env) });
}
