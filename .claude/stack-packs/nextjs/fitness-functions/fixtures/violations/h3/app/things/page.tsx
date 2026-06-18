// 違反候補(SHOULD/warn): page の常時 force-dynamic + データ取得 segment に error.tsx 無し。
export const dynamic = 'force-dynamic';

export default async function ThingsPage() {
  const res = await fetch('https://example.com/things', { cache: 'no-store' });
  const things = await res.json();
  return <ul>{things.map((t: any) => <li key={t.id}>{t.name}</li>)}</ul>;
}
