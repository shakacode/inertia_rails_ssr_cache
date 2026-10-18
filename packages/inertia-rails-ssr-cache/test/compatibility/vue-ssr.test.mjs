import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createInertiaApp } from '@inertiajs/vue3';
import { createSSRApp, h } from 'vue';
import { renderToString } from 'vue/server-renderer';
import { guardRelease, ReleaseMismatchError } from '../../src/index.ts';

// Runtime check that the guard drives a real Inertia Vue 3 SSR render. Plain
// JavaScript, like spec/fixtures/ssr.mjs: inertia-types.ts holds the strict
// callback type check. Svelte is type-checked only, because its adapter ships
// uncompiled runes modules that plain Node cannot load.
const Greeting = {
  props: { message: { type: String, required: true } },
  setup: (props) => () => h('main', props.message),
};

function guardedVueRender(release) {
  return guardRelease(release, (page) =>
    createInertiaApp({
      page,
      render: renderToString,
      resolve: () => Greeting,
      setup: ({ App, props, plugin }) => createSSRApp({ render: () => h(App, props) }).use(plugin),
    }),
  );
}

const page = {
  component: 'Greeting',
  props: { message: 'Hello from Vue', errors: {} },
  url: '/',
  version: 'build-42',
};

await test('renders Inertia Vue 3 SSR through the guard', async () => {
  const result = await guardedVueRender('build-42')(page);
  assert.match(result.body, /<main>Hello from Vue<\/main>/);
});

await test('rejects a mismatched Vue page before rendering', () => {
  assert.throws(() => guardedVueRender('build-43')(page), ReleaseMismatchError);
});
