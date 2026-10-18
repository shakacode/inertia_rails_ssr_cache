# inertia-rails-ssr-cache

Companion to the [`inertia_rails_ssr_cache`](https://rubygems.org/gems/inertia_rails_ssr_cache) gem. Wrap your
existing Inertia server callback to reject a page sent to the wrong SSR bundle.
This package does not start a server or create another cache.

```typescript
import { guardRelease } from 'inertia-rails-ssr-cache';
import createServer from '@inertiajs/react/server';

createServer(guardRelease('build-42', renderPage));
```

Embed the release token in the bundle **at build time**, and use exactly the same
value for Rails `InertiaRails.configuration.version`. Reading a deployment-wide
environment value at runtime does not prove which JavaScript was built.

`guardRelease(expectedRelease, render)` retains the callback's page type and
returns its synchronous value or original promise. Mismatched, missing, null,
or nonstring page versions throw `ReleaseMismatchError` before rendering. Build
tokens must be 1–128 ASCII letters, digits, dots, underscores or hyphens and start
with a letter or digit. Errors exclude page props and HTML.

The callback runs on native cache misses. It cannot certify entries written by
an earlier unguarded renderer. Deploy with a fresh immutable version when adding
the guard, keep the cache shared between warming and web processes, and retain
the previous guarded bundle/version for rollback.

Node 22.18+; ESM only. The callback type is checked against the `createServer`
callbacks of Inertia React, Vue 3 and Svelte 3.9.1, and a Node test renders a
Vue 3 page through the guard. The Rails integration suite runs React only. No
framework runtime dependencies are required. Install the same version as the gem.

Version 0.1.0 is an early release; see the gem's adopter pilot guidance before
production use.

Licensed under [The Inertia Rails SSR Cache License](LICENSE.md): free for
development, test and CI, and for production use by small organizations,
charities, schools and hospitals. Other production use is covered by a ShakaStack Pro
subscription for organizations under 250 people and $10M revenue; see [pro.reactonrails.com](https://pro.reactonrails.com/).
