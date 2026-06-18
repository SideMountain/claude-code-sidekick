// 正当（dogfood 由来）: 接続文字列の「値」は出さず、ラベル / 存在チェックのみ。
// これらは H1 error にしない（warn は可）。bare 値ログだけが error。
export function checkDb() {
  console.log('[x] Checking DATABASE_URL...');
  console.log('[x] DATABASE_URL exists:', !!process.env.DATABASE_URL);
  if (!process.env.DATABASE_URL) {
    console.error('[x] DATABASE_URL is not set!');
  }
}
