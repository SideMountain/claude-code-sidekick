// 違反: inline 'use server' が col-0（インデント無し）でも検出されること（旧実装は whitespace 依存で見逃した）。
export function Form() {
  async function save() {
'use server';
    return 1;
  }
  return <button onClick={save}>save</button>;
}
