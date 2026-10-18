import { Head } from '@inertiajs/react';
import { createElement as h, Fragment, useState } from 'react';

// Replaced with a literal by build.mjs, independently of runtime Rails configuration.
declare const DEMO_BUILD_RELEASE: string;

interface DemoProps {
  message: string;
  release: string;
}

export default function Demo({ message, release }: DemoProps) {
  const [clicks, setClicks] = useState(0);

  return h(
    Fragment,
    null,
    h(Head, { title: 'SSR cache lab' }),
    h(
      'main',
      { className: 'lab', 'data-build': DEMO_BUILD_RELEASE },
      h(
        'header',
        { className: 'masthead' },
        h(
          'a',
          { href: '/', className: 'wordmark' },
          h('span', { 'aria-hidden': true }, '↗'),
          ' SSR cache lab',
        ),
        h('span', { className: 'local-label' }, 'Local demo'),
      ),
      h(
        'section',
        { className: 'intro', 'aria-labelledby': 'page-title' },
        h('p', { className: 'eyebrow' }, 'INERTIA RAILS × ACTIVE JOB'),
        h('h1', { id: 'page-title' }, message),
        h(
          'p',
          { className: 'lede' },
          'Render once in a worker. Reuse the same SSR entry in a separate web process. Then let React take over.',
        ),
        h('p', { className: 'release' }, 'Release ', h('code', null, release)),
      ),
      h(
        'section',
        { className: 'experiment', 'aria-labelledby': 'experiment-title' },
        h('h2', { id: 'experiment-title' }, 'One route. Three steps.'),
        h(
          'ol',
          { className: 'steps' },
          h(
            'li',
            null,
            h('h3', null, 'Enqueue'),
            h('p', null, 'Submit the warmer through Active Job with ', h('code', null, 'bin/demo warm'), '.'),
          ),
          h(
            'li',
            null,
            h('h3', null, 'Warm'),
            h(
              'p',
              null,
              'The worker verifies that two fresh Rails requests reuse one native SSR cache entry.',
            ),
          ),
          h(
            'li',
            null,
            h('h3', null, 'Visit'),
            h('p', null, 'Reload this page and check the proof output for reuse across processes.'),
          ),
        ),
      ),
      h(
        'section',
        { className: 'hydration', 'aria-labelledby': 'hydration-title' },
        h(
          'div',
          null,
          h('h2', { id: 'hydration-title' }, 'HTML first. Interaction next.'),
          h('p', null, 'Click to confirm that the server-rendered page hydrated in your browser.'),
        ),
        h(
          'button',
          {
            type: 'button',
            onClick: () => {
              setClicks((count) => count + 1);
            },
            'aria-live': 'polite',
          },
          `Hydration clicks: ${String(clicks)}`,
        ),
      ),
      h(
        'footer',
        null,
        'This page displays the experiment steps, not live cache status. SSR cache hits still run Rails controllers and props.',
      ),
    ),
  );
}
