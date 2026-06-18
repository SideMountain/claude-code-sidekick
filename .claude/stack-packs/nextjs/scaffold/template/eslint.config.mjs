// Next.js 16 で `next lint` は廃止 → ESLint を直接使う（flat config）。
// create-next-app と同形（FlatCompat 経由で eslint-config-next を読み込む）。
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { FlatCompat } from '@eslint/eslintrc';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const compat = new FlatCompat({ baseDirectory: __dirname });

const eslintConfig = [
  ...compat.extends('next/core-web-vitals', 'next/typescript'),
  { ignores: ['.next/**', 'node_modules/**'] },
];

export default eslintConfig;
