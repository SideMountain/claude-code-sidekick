'use client';
// 違反: page が useEffect + fetch で自前データ取得している（server-first 違反）。
import { useEffect, useState } from 'react';

export default function ThingsPage() {
  const [things, setThings] = useState([]);
  useEffect(() => {
    fetch('/api/things').then((r) => r.json()).then((d) => setThings(d.data));
  }, []);
  return <ul>{things.map((t: any) => <li key={t.id}>{t.name}</li>)}</ul>;
}
