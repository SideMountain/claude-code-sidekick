// characterization corpus: check 3 (empty catch), single-line only
export async function a() {
  try { await work() } catch {}
}
export async function b() {
  try { await work() } catch (e) {}
}
export async function c() {
  try { await work() } catch (err) { report(err) }
}
export function d() {
  return work().catch(() => {})
}
export function e() {
  return work().catch(function (err) {})
}
export function f() {
  return work().catch((err) => report(err))
}
export function g() {
  try {
    work()
  } catch (err) {
  }
}
export function h() {
  const CATCH = {}
  return CATCH
}
export function i() {
  try { work() } CATCH (e) {}
  return work().CATCH(() => {})
}
