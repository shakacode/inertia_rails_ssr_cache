import { appendFileSync } from 'node:fs';
import { createElement, Fragment } from 'react';
import { renderToString } from 'react-dom/server';
import { createInertiaApp, Head } from '@inertiajs/react';
import createServer from '@inertiajs/react/server';
import { guardRelease } from '../../packages/inertia-rails-ssr-cache/dist/index.js';

// The test builds a separate entry module with a literal release for each process.
export function startFixture(release, port, countFile) {
  function FixturePage({ message, cookie, nonce }) {
    return createElement(
      Fragment,
      null,
      createElement(Head, { title: `Fixture ${release}` }),
      createElement(
        'main',
        { 'data-build': release },
        createElement('h1', null, message),
        createElement('p', null, `Cookie: ${cookie}`),
        createElement('p', null, `Nonce: ${nonce}`),
      ),
    );
  }

  createServer(
    guardRelease(release, (page) => {
      appendFileSync(countFile, `${JSON.stringify({ version: page.version, url: page.url })}\n`);
      if (page.component === 'Null') return null;
      if (page.component === 'False') return false;
      if (page.component === 'Broken') {
        throw new Error('Intentional fixture SSR failure');
      }
      return createInertiaApp({
        page,
        render: renderToString,
        resolve: () => FixturePage,
        setup: ({ App, props }) => createElement(App, props),
      });
    }),
    { host: '127.0.0.1', port, formatErrors: true },
  );
}
