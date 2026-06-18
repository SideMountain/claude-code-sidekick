// architecture.test.ts — 下流PJ 向け vitest ラッパー（ARCHITECTURE.md の `__tests__/architecture/*.test.ts` を満たす）。
//
// 配置: このファイルを下流PJ の `__tests__/architecture/architecture.test.ts` にコピーする。
// 実体ロジックは pack の checks.js（依存ゼロの plain Node）。vitest を使わず CI に挿すなら
// `node .claude/stack-packs/nextjs/fitness-functions/run-fitness.js .`（= npm run test:arch）でよい。
//
// 1 ルール = 1 test。error（HARD）があれば fail。warn（SHOULD/SOFT）は run-fitness 側で可視化する。
import { describe, it, expect } from 'vitest';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const PACK = path.resolve(process.cwd(), '.claude/stack-packs/nextjs/fitness-functions/checks.js');
const { runAll } = require(PACK) as { runAll: (root: string) => Array<{ rule: string; title: string; findings: Array<{ severity: string; file: string; line: number; message: string }> }> };

describe('architecture fitness (ARCHITECTURE.md golden path)', () => {
  const results = runAll(process.cwd());
  for (const r of results) {
    it(`${r.rule} ${r.title}`, () => {
      const errors = r.findings.filter((x) => x.severity === 'error');
      const detail = errors.map((e) => `  ${e.file}:${e.line} ${e.message}`).join('\n');
      expect(errors, `\n${detail}`).toHaveLength(0);
    });
  }
});
