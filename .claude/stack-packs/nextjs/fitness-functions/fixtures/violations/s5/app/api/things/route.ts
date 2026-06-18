// 違反: 生セッション読み取り（getServerSession）が auth helper の外。role を文字列リテラルで比較。
import { getServerSession } from 'next-auth';

export async function GET() {
  const session = await getServerSession();
  const user = session?.user as { role: string } | undefined;
  if (user?.role === 'ADMIN') {
    return Response.json({ ok: true });
  }
  return new Response('forbidden', { status: 403 });
}
