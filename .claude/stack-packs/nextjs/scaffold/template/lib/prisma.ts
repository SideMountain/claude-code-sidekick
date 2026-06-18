// H1: 単一 Prisma シングルトン。`new PrismaClient` はこのファイルにのみ存在してよい。
// 接続文字列を console.log しない。dev のみ globalThis にキャッシュ（HMR の接続枯渇回避）。
import 'server-only';
import { PrismaClient } from '@prisma/client';

function createClient() {
  // 論理削除（H1・SHOULD）: deletedAt=null を **read 系全オペ** のクエリ境界に自動注入し、
  // callsite の手書きを禁止する。注入対象 = findMany / findFirst / count / aggregate / groupBy。
  // findUnique は where に非 unique 列（deletedAt）を取れない（Prisma の制約）ため、
  // **soft-delete 対象 model では findUnique を使わず findFirst を使う**（getPostByIdForCompany 参照）。
  return new PrismaClient().$extends({
    query: {
      post: {
        async findMany({ args, query }) { args.where = { deletedAt: null, ...args.where }; return query(args); },
        async findFirst({ args, query }) { args.where = { deletedAt: null, ...args.where }; return query(args); },
        async count({ args, query }) { args.where = { deletedAt: null, ...args.where }; return query(args); },
        async aggregate({ args, query }) { args.where = { deletedAt: null, ...args.where }; return query(args); },
        async groupBy({ args, query }) { args.where = { deletedAt: null, ...args.where }; return query(args); },
      },
    },
  });
}

// 拡張クライアントの型をそのまま使う（`as unknown as PrismaClient` の force-cast を避ける）。
const globalForPrisma = globalThis as unknown as { prisma?: ReturnType<typeof createClient> };

export const prisma = globalForPrisma.prisma ?? createClient();

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma;
