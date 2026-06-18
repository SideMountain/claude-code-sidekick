// DAL (S2): HTTP 非依存のデータ取得層。route は prisma を直接触らず、ここを呼ぶ。
// S6: object-level authz — 取得関数は必ず tenant/owner スコープ（companyId）を where に持つ。
//     直URL / ID 推測でも認可外の行は返らない。
// S8: 命名ブリッジ — 関数名に主 model（Post）を encode し、API→table を grep で辿れるようにする。
import 'server-only';
import { prisma } from '@/lib/prisma';
import type { SessionCtx } from '@/lib/auth/session';

/** model: Post — 呼び出し主体の company にスコープした一覧。 */
export async function listPostsForCompany(ctx: SessionCtx, limit = 20) {
  return prisma.post.findMany({
    where: { companyId: ctx.companyId },
    orderBy: { createdAt: 'desc' },
    take: limit,
  });
}

/** model: Post — id 取得も company スコープを必ず通す（IDOR 防止）。 */
export async function getPostByIdForCompany(ctx: SessionCtx, id: string) {
  return prisma.post.findFirst({
    where: { id, companyId: ctx.companyId },
  });
}
