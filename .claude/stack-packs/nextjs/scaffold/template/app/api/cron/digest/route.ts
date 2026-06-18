// S4: cron = scheduler trigger（vercel.json crons[] が叩く）。page から辿れない mutation → 列挙対象。
// S2: route は prisma 直叩きせず DAL（sendPendingDigests）へ委譲。
// out-of-band auth realm（S5 残余）: cron secret で保護。多重起動前提で DAL 側を冪等に。
import { sendPendingDigests } from '@/lib/digest/send';

export async function GET(req: Request) {
  if (req.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`) {
    return new Response('unauthorized', { status: 401 });
  }
  const sent = await sendPendingDigests();
  return Response.json({ ok: true, sent });
}
