import type { NextConfig } from 'next';

// Rendering baseline = 従来モデル（`export const dynamic` / `revalidate`）。
// Cache Components（`use cache` / `cacheLife`）は opt-in な将来パス（採用時に golden path 前提として宣言）。
const nextConfig: NextConfig = {
  // reactStrictMode は既定 true。
};

export default nextConfig;
