// 違反: コンポーネント内 inline 'use server' クロージャ（grep 列挙不能）。
export function Widget() {
  async function save() {
    'use server';
    // ...
  }
  return <button onClick={save}>save</button>;
}
