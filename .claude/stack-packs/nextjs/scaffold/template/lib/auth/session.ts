// S5: 認証コアは「単一 helper」経由。セッション/role の読み取りはこのファイルに集約し、
// route / page に inline 複製しない。role は Prisma enum で比較（文字列リテラル禁止）。
// allowlist のみ（default-deny）・discriminated-union 返り。
//
// 認証ライブラリ非依存: `readRawSession()` を next-auth / Auth.js v5 / Better Auth / Clerk 等で実装する。
// 生のセッション読み取り（getServerSession / auth() 等）は **この seam の内側だけ** に置く（S5 検証）。
import 'server-only';
import { Role } from '@prisma/client';

export type SessionCtx = { userId: string; companyId: string; role: Role };

export type AuthResult =
  | { ok: true; ctx: SessionCtx }
  | { ok: false; response: Response };

const unauthorized = (): AuthResult => ({
  ok: false,
  response: Response.json({ error: 'unauthorized' }, { status: 401 }),
});
const forbidden = (): AuthResult => ({
  ok: false,
  response: Response.json({ error: 'forbidden' }, { status: 403 }),
});

// 認証ライブラリの生セッション読み取り seam（ここを各 PJ が実装する）。
async function readRawSession(): Promise<SessionCtx | null> {
  // 例: const s = await getServerSession(authOptions);
  //     return s ? { userId: s.user.id, companyId: s.user.companyId, role: s.user.role } : null;
  return null;
}

/** 認証必須。未認証なら 401 を内包した失敗を返す。 */
export async function requireSession(): Promise<AuthResult> {
  const ctx = await readRawSession();
  if (!ctx) return unauthorized();
  return { ok: true, ctx };
}

/** 指定 role の allowlist（default-deny）。 */
export async function requireRole(allowed: Role[]): Promise<AuthResult> {
  const res = await requireSession();
  if (!res.ok) return res;
  if (!allowed.includes(res.ctx.role)) return forbidden();
  return res;
}
