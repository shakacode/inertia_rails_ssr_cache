# Changelog

All notable changes to the `inertia_rails_ssr_cache` gem and the
`inertia-rails-ssr-cache` npm package. Both ship at the same version.

## 0.1.0 — 2026-10-18

First public release. An early release: run the
[adopter pilot](docs/releasing.md#adopter-pilot-before-production-use) before
production use.

- `InertiaRailsSsrCache.warm_later` and the `inertia_rails_ssr_cache:warm` task
  enqueue one Active Job job that warms up to 50 registered public paths and
  verifies that a fresh anonymous request reuses each native Inertia SSR cache
  entry.
- Per-target results and `target.inertia_rails_ssr_cache` /
  `warm.inertia_rails_ssr_cache` notifications; a failed run raises
  `InertiaRailsSsrCache::WarmFailed`.
- Queued jobs carry their intended release and recheck it at execution.
- npm `guardRelease` wraps the Inertia SSR callback and throws
  `ReleaseMismatchError` when the page version differs from the built bundle.
- Tested with Ruby 3.3+, Rails 7.2–8.1, `inertia_rails` 3.22.x and Inertia React
  3.9.1; the guard's types are checked against Inertia React, Vue 3 and Svelte
  3.9.1, and a Vue 3 page renders through it in a Node test.
- Licensed under The Inertia Rails SSR Cache License 1.0.
