// DAL 書き込み側 (S2/S6): mutation も company スコープを強制する。
// S8: 命名ブリッジ — 関数名に model（Post）を encode。
import 'server-only';
import { prisma } from '@/lib/prisma';
import type { SessionCtx } from '@/lib/auth/session';
import type { CreatePostInput } from '@/lib/validations/post';

/** model: Post — 作成。author/company は ctx から付与（client 入力を信用しない）。 */
export async function createPost(ctx: SessionCtx, input: CreatePostInput) {
  return prisma.post.create({
    data: {
      title: input.title,
      body: input.body,
      authorId: ctx.userId,
      companyId: ctx.companyId,
    },
  });
}

/** model: Post — 論理削除。company スコープ条件付き（認可外は 0 件 = no-op）。 */
export async function softDeletePost(ctx: SessionCtx, id: string) {
  return prisma.post.updateMany({
    where: { id, companyId: ctx.companyId },
    data: { deletedAt: new Date() },
  });
}
