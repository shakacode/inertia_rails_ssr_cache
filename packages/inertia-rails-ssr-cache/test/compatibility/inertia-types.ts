import assert from 'node:assert/strict';
import type { Page } from '@inertiajs/core';
import type createReactServer from '@inertiajs/react/server';
import type createSvelteServer from '@inertiajs/svelte/server';
import type createVueServer from '@inertiajs/vue3/server';
import { guardRelease } from '../../src/index.ts';

// Inertia apps bundle SSR; upstream declarations use extensionless imports.
// Our own library is separately checked and built with NodeNext resolution.
// The guard must fit each adapter's createServer callback without casts.
type ReactRender = Parameters<typeof createReactServer>[0];
type VueRender = Parameters<typeof createVueServer>[0];
type SvelteRender = Parameters<typeof createSvelteServer>[0];

const ssr = (page: Page) => Promise.resolve({ head: [], body: `<main>${page.component}</main>` });

const renders: [ReactRender, VueRender, SvelteRender] = [
  guardRelease('build-42', ssr),
  guardRelease('build-42', ssr),
  guardRelease('build-42', ssr),
];
for (const render of renders) assert.equal(typeof render, 'function');
