'use server';
// 違反: module-level 'use server' が actions.ts ではないファイルにある。
export async function doThing(id: string) {
  return id;
}
