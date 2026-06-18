// 違反: route が @/lib/prisma を直接 import（DAL を経由していない）。
import { prisma } from '@/lib/prisma';

export async function GET() {
  const things = await prisma.thing.findMany();
  return Response.json({ data: things });
}
