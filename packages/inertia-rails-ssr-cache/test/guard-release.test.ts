import assert from 'node:assert/strict';
import { test } from 'node:test';
import { guardRelease, ReleaseMismatchError } from '../src/index.ts';

await test('rejects an old SSR bundle before application rendering', () => {
  let renders = 0;
  const render = guardRelease('release-new', (page: { version: string }) => {
    renders += 1;
    return page.version;
  });
  assert.throws(() => render({ version: 'release-old' }), ReleaseMismatchError);
  assert.equal(renders, 0);
});

await test('preserves the entire page and synchronous result by identity', () => {
  const page = { version: 'build-42', props: { label: 'hello' }, component: 'Home' };
  const response = { head: ['<title>Hello</title>'], body: '<main>Hello</main>' };
  const render = guardRelease('build-42', (received: typeof page) => {
    assert.equal(received, page);
    return response;
  });
  assert.equal(render(page), response);
});

await test('preserves the original promise without awaiting or wrapping it', async () => {
  const promise = Promise.resolve({ head: [], body: '<main>SSR</main>' });
  const render = guardRelease('build-42', () => promise);
  assert.equal(render({ version: 'build-42' }), promise);
  assert.deepEqual(await promise, { head: [], body: '<main>SSR</main>' });
});

await test('preserves application exceptions', () => {
  const error = new Error('application render failed');
  const render = guardRelease('build-42', () => {
    throw error;
  });
  assert.throws(
    () => render({ version: 'build-42' }),
    (caught: unknown) => caught === error,
  );
});

await test('rejects missing, null, nonstring and mismatched versions', () => {
  let renders = 0;
  const render = guardRelease('build-42', (page: { version?: unknown }) => {
    renders += 1;
    return page.version;
  });
  for (const page of [{}, { version: null }, { version: 42 }, { version: '' }, { version: 'build-41' }]) {
    assert.throws(() => render(page), ReleaseMismatchError);
  }
  assert.equal(renders, 0);
});

await test('rejects invalid build tokens at wrapper creation', () => {
  for (const release of ['', ' ', 'build\n42', '<script>', 'a'.repeat(129)]) {
    assert.throws(() => guardRelease(release, () => 'never called'), TypeError);
  }
});

await test('accepts normal release and asset digest tokens', () => {
  for (const release of ['a', '2026.10.12_abc-42', 'a'.repeat(128)]) {
    const render = guardRelease(release, () => 'rendered');
    assert.equal(render({ version: release }), 'rendered');
  }
});
