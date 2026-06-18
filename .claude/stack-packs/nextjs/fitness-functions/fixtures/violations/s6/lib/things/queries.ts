// 違反候補(SOFT/warn): 単一エンティティ取得が tenant/owner スコープを欠く（IDOR 懸念）。
import 'server-only';
import { prisma } from '@/lib/prisma';

export async function getThingById(id: string) {
  return prisma.thing.findFirst({ where: { id } });
}
