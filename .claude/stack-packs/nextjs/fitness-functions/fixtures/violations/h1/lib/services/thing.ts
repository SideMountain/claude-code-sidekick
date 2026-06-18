// 違反: new PrismaClient が singleton（lib/prisma.ts）の外。接続文字列を console 出力。
import { PrismaClient } from '@prisma/client';

export const db = new PrismaClient();
console.log('connecting to', process.env.DATABASE_URL);
