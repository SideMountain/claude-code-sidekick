// 違反: route 内に z.object literal（lib/validations から import すべき）。
import { z } from 'zod';

const schema = z.object({ name: z.string() });

export async function POST(req: Request) {
  const parsed = schema.safeParse(await req.json());
  if (!parsed.success) return new Response('bad', { status: 400 });
  return Response.json({ data: parsed.data });
}
