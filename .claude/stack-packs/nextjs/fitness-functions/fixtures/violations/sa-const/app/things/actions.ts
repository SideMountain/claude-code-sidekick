'use server';
// actions.ts に module-level action 1 つ + データ const（action ではない）。
// 正準カウントは serverActions=1（MAX を action と数えない）。
export const MAX = 10;
export async function doThing(id: string) {
  return id;
}
