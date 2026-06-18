// 違反: 同一行 inline 'use server' クロージャ（旧実装は行頭 whitespace アンカーで見逃した）。
export function Widget() {
  const act = async () => { 'use server'; return 1; };
  return <button onClick={act}>x</button>;
}
