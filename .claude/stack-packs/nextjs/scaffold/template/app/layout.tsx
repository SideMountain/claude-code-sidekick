// Root layout（フレームワーク強制 convention）。
// H3: 認証境界・sidebar 有無等は route group `(group)` + per-segment layout.tsx で表現する。
//     layout が usePathname() + ハードコード prefix 配列で分岐するのは禁止。
export const metadata = { title: 'App' };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ja">
      <body>{children}</body>
    </html>
  );
}
