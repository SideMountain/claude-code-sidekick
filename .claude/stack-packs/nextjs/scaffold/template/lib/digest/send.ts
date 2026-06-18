// DAL (S2): cron から呼ばれる集計 + 送信層。route は prisma を触らずここを呼ぶ。
// 多重起動前提（cron は at-least-once）→ 送信済みフラグ等で冪等に（H2）。
import 'server-only';
import { prisma } from '@/lib/prisma';

/** model: Post — 直近分を集計して digest 送信。送信件数を返す。 */
export async function sendPendingDigests(): Promise<number> {
  const recent = await prisma.post.findMany({
    orderBy: { createdAt: 'desc' },
    take: 100,
  });
  // ... 送信副作用（冪等に）
  return recent.length;
}
