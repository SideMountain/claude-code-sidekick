// DAL (S2): webhook の冪等処理層。route は署名検証 + 委譲のみで、ここが DB と副作用を持つ。
// H2: event-id を永続化して replay を短絡。行も副作用も同 tx 内で冪等に。
import 'server-only';
import { prisma } from '@/lib/prisma';

export type BillingEvent = { id: string; type?: string };

/** model: WebhookEvent — 既処理なら短絡、未処理なら event 記録 + 副作用を同 tx で実行。 */
export async function processBillingEvent(event: BillingEvent): Promise<{ deduped: boolean }> {
  // authz-ok: 冪等性キー（provider 側 event-id = PK）。署名で gated 済みでテナント資源ではない
  const seen = await prisma.webhookEvent.findUnique({ where: { id: event.id } });
  if (seen) return { deduped: true };

  await prisma.$transaction(async (tx) => {
    await tx.webhookEvent.create({ data: { id: event.id, provider: 'billing' } });
    // ... 課金照合等の副作用も同 tx 内（DB 行も副作用も冪等に）
  });
  return { deduped: false };
}
