// S2: route handler は 認証ゲート → バリデーション → service 呼び → レスポンス整形 のみ。
//     @/lib/prisma を import しない（DB アクセスは DAL = lib/posts/*）。
// S7: schema は lib/validations から import（route 内 z.object 禁止）。body は safeParse。
import { requireSession } from '@/lib/auth/session';
import { createPostSchema, listPostsQuerySchema } from '@/lib/validations/post';
import { listPostsForCompany } from '@/lib/posts/queries';
import { createPost } from '@/lib/posts/mutations';

export async function GET(req: Request) {
  const auth = await requireSession();
  if (!auth.ok) return auth.response;

  const url = new URL(req.url);
  const parsed = listPostsQuerySchema.safeParse(Object.fromEntries(url.searchParams));
  if (!parsed.success) return Response.json({ error: 'invalid query' }, { status: 400 });

  const data = await listPostsForCompany(auth.ctx, parsed.data.limit);
  return Response.json({ data });
}

export async function POST(req: Request) {
  const auth = await requireSession();
  if (!auth.ok) return auth.response;

  const parsed = createPostSchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return Response.json({ error: 'invalid body' }, { status: 400 });

  const post = await createPost(auth.ctx, parsed.data);
  return Response.json({ data: post }, { status: 201 });
}
