'use client';
// H3: app 全体の最終防壁を 1 つ。個別 segment の error.tsx と併用する
//     （global-error.tsx だけで個別境界ゼロは是正対象）。
export default function GlobalError({ reset }: { error: Error; reset: () => void }) {
  return (
    <html lang="ja">
      <body>
        <h2>予期しないエラーが発生しました。</h2>
        <button onClick={reset}>再読み込み</button>
      </body>
    </html>
  );
}
