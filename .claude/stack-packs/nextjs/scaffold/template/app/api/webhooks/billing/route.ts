// S4: webhook = provider-callback trigger。page から辿れないが blast-radius 大 → mutation 列挙対象。
// S2: route は prisma を直接触らない。冪等性ロジックも DAL（processBillingEvent）に委譲。
// H2: at-least-once 配信前提。冪等性は DAL が event-id 永続化 + 同 tx で担保。
import { processBillingEvent } from '@/lib/billing/webhook';

export async function POST(req: Request) {
  // out-of-band auth realm（S5 残余）: provider 署名検証。
  if (!verifySignature(req)) return new Response('bad signature', { status: 400 });

  const event = await req.json().catch(() => null);
  if (!event?.id) return Response.json({ error: 'invalid event' }, { status: 400 });

  const { deduped } = await processBillingEvent(event);
  return Response.json({ ok: true, deduped });
}

function verifySignature(_req: Request): boolean {
  // 例: stripe.webhooks.constructEvent(body, sig, secret) 等で検証する。
  return true;
}
