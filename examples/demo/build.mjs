import { mkdir } from 'node:fs/promises';
import { isAbsolute, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const runtime = process.env.DEMO_RUNTIME;
const release = process.env.APP_RELEASE ?? 'demo-v1';
if (!runtime || !isAbsolute(runtime)) throw new Error('DEMO_RUNTIME must be an absolute directory path.');
if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/.test(release)) throw new Error('Invalid APP_RELEASE.');
await mkdir(join(runtime, 'public/assets'), { recursive: true });

const common = {
  absWorkingDir: fileURLToPath(new URL('.', import.meta.url)),
  bundle: true,
  format: 'esm',
  define: { DEMO_BUILD_RELEASE: JSON.stringify(release), 'process.env.NODE_ENV': '"production"' },
  logLevel: 'warning',
};
await build({
  ...common,
  entryPoints: ['frontend/client.ts'],
  outfile: join(runtime, 'public/assets/demo.js'),
  platform: 'browser',
  target: 'es2022',
  minify: true,
});
await build({
  ...common,
  entryPoints: ['frontend/ssr.ts'],
  outfile: join(runtime, 'ssr.mjs'),
  platform: 'node',
  target: 'node22',
  banner: {
    js: 'import { createRequire } from "node:module"; const require = createRequire(import.meta.url);',
  },
});
