// 違反: URL 正規表現の // が同一行の実違反を潰さないこと（comment-stripper の regex 状態を検証）。
export async function GET() {
  const u = 'x';
  const role = 'admin';
  const ok = /^https?:\/\//.test(u) && role === 'admin';
  return Response.json({ ok });
}
