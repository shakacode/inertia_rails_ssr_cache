import { appendFileSync } from 'node:fs';
import { isAbsolute, join } from 'node:path';
import { createInertiaApp } from '@inertiajs/react';
import createServer from '@inertiajs/react/server';
import { createElement } from 'react';
import { renderToString } from 'react-dom/server';
import { guardRelease } from '../../../packages/inertia-rails-ssr-cache/dist/index.js';
import Demo from './page.js';

declare const DEMO_BUILD_RELEASE: string;

const runtime = process.env.DEMO_RUNTIME;
const port = Number(process.env.DEMO_SSR_PORT ?? '13373');
if (!runtime || !isAbsolute(runtime)) throw new Error('DEMO_RUNTIME must be an absolute directory path.');
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Invalid DEMO_SSR_PORT.');

createServer(
  guardRelease(DEMO_BUILD_RELEASE, (page) => {
    appendFileSync(
      join(runtime, 'renders.jsonl'),
      `${JSON.stringify({ version: page.version, url: page.url, pid: process.pid })}\n`,
    );
    return createInertiaApp({
      page,
      render: renderToString,
      resolve: (name) => {
        if (name !== 'Demo') throw new Error(`Unknown demo page: ${name}`);
        return Demo;
      },
      setup: ({ App, props }) => createElement(App, props),
    });
  }),
  { host: '127.0.0.1', port, formatErrors: true },
);
