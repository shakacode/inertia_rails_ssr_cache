# Inertia Rails SSR Cache

Warm the server-side rendering (SSR) cache of an Inertia Rails app after each
deploy, so the first visitors to your public pages get cached SSR HTML instead of
waiting for Node to render it.

You list the public paths to warm. One Active Job job requests each path the way an
anonymous visitor would and checks that a second, fresh request reuses the same
cache entry Inertia wrote. Inertia keeps owning page serialization, cache keys and
cache writes; this gem only drives and verifies them. A small npm companion,
`guardRelease`, wraps your Node SSR callback so a page from one release is never
rendered by another release's bundle.

Version 0.1.0 is an early release. Run the
[adopter pilot](docs/releasing.md#adopter-pilot-before-production-use) with your
own routes, cache topology and load before enabling warming in production.

Works with any Active Job backend; there is no Sidekiq requirement. GQL LRU warming
is out of scope.

## What is tested

- Ruby 3.3+, Rails 7.2–8.1 and `inertia_rails` 3.22.x.
- The Rails integration suite runs against Inertia React 3.9.1, including reuse
  of a FileStore cache from a separate web process.
- The `guardRelease` callback type is checked against the `createServer`
  callbacks of Inertia React, Vue 3 and Svelte 3.9.1. A Node test renders a Vue 3
  page through the guard. Svelte is checked for types only.
- Node 22.18+; the npm package is ESM only.

## Installation

```ruby
# Gemfile
gem "inertia_rails_ssr_cache", "~> 0.1.0"
```

```sh
bundle install
npm install inertia-rails-ssr-cache@0.1.0
```

Install the same version of both packages.

## Application setup

Configure Inertia normally. Use an immutable release token embedded in the SSR
bundle and a retaining cache store shared by warming workers and web processes.
Warming requires `config.enable_reloading = false` and
`config.allow_concurrency` must not be `false`. Enqueueing and execution reject
these unsupported settings: nested requests can deadlock against the surrounding
job's Rails reload or concurrency locks.

```ruby
# config/initializers/inertia.rb
InertiaRails.configure do |config|
  config.ssr_enabled = true
  config.ssr_cache = { expires_in: 1.hour }
  config.version = ENV.fetch("APP_RELEASE")
end

# config/initializers/inertia_rails_ssr_cache.rb
InertiaRailsSsrCache.configure do |config|
  config.origin = "https://www.example.com"
  config.paths = ["/", "/pricing", "/features"]
  config.queue_name = :ssr_warming
end
```

Wrap your existing Node SSR callback:

```typescript
import { guardRelease } from 'inertia-rails-ssr-cache';
import createServer from '@inertiajs/react/server';

// Replace with a literal or bundler-defined value embedded during the build.
createServer(guardRelease('build-42', renderPage));
```

The embedded value must equal Rails' `APP_RELEASE`. A runtime environment value
alone cannot identify which JavaScript was built. Deploy with a fresh version
when first adding the guard; cache hits do not execute the callback, so it cannot
certify old entries written by an unguarded renderer.

After the candidate Rails workers, SSR service and database are ready:

```ruby
job_id = InertiaRailsSsrCache.warm_later
```

Or enqueue through the Rails task:

```sh
bin/rails inertia_rails_ssr_cache:warm
```

The returned job ID confirms enqueueing, not completion. Monitor normal Active
Job failures and `target.inertia_rails_ssr_cache` / `warm.inertia_rails_ssr_cache`
notifications. Target results report a reason such as `reused`,
`missing_cache_evidence`, `cache_key_changed`, `cache_not_reused`, `http_failure`,
`release_mismatch` or `invalid_ssr_value`. A failed run raises
`InertiaRailsSsrCache::WarmFailed` with its report. Events contain target/result
metadata, not page props or HTML.

## What verification means

Each job processes at most 50 distinct registered paths sequentially. Each path
gets two fresh anonymous HTML GETs through the full Rails middleware stack,
without credentials, cookie carry-over, Inertia visit headers or redirect
following. The synthetic Rack environment uses source address `192.0.2.1` and no
User-Agent header. Both responses must be HTTP 200 HTML. Each must produce exactly one
native SSR cache-fetch observation, and the second must hit the first one's key.
The retained entry must also contain a string body and an array of string head
entries; cached null/false values do not qualify.

This catches normal client-rendering fallback, disabled/nonretaining caches and
unstable page data. Success describes observed reuse at that moment; eviction,
expiry and future request variants can still cause misses. The application must
approve safe public GETs and deterministic anonymous props that do not vary by
client IP, geolocation or browser identity. Context-dependent
Inertia versions are unsupported: worker and controller versions must agree.

A native SSR hit avoids Node rendering. Controllers, queries and prop resolution
still execute. This package makes no database-cache or production latency claim.

## Operational limits

- Concurrency is one request per job. Multiple jobs can overlap; configure a
  dedicated queue's concurrency in your Active Job backend.
- Each request uses a fresh joined thread to preserve the surrounding job's
  Rails executor and CurrentAttributes. Allow for an additional database
  connection if job callbacks retain one while waiting for the request.
- Route count is bounded, but execution has no hard wall-clock deadline.
  Inertia Rails 3.22 uses its HTTP client's timeouts. The warmer does not interrupt
  Rails requests with asynchronous Ruby timeouts. If the host interrupts a job,
  it waits for its active request to finish before unwinding; shutdown can be
  delayed by the remaining request duration.
- Readiness, migrations, replica lag, cutover and cancellation remain deployment
  responsibilities. No scheduler, distributed lock or durable run registry is
  installed. Retrying repeats eligible GETs and reuses entries already present.
- Queued jobs carry their intended release and recheck it at execution. Rollbacks
  use the matching guarded bundle and immutable Inertia version.
- Worker and web cache topology must match. MemoryStore only warms one process;
  the integration suite proves reuse with FileStore across separate processes.
- Native cache instrumentation compatibility is intentionally limited to the
  tested Inertia Rails 3.22 line. A future adapter upgrade needs contract tests.
- Cache namespaces must be absent or static strings. Callable namespaces and
  custom key encodings cannot be verified. FileStore support covers the built-in
  class with keys that fit in one encoded filename. Longer keys and subclasses
  are unsupported and can fail verification even if native caching works.

## Development

Ruby 3.3+, Rails 7.2–8.1, `inertia_rails` 3.22.x, Node 22.18+ and the pnpm version
pinned in `package.json`. The Rails integration fixture and demo use Inertia React
3.9.1. The npm guard is also type-checked against Inertia Vue 3 and Svelte 3.9.1,
and renders a Vue 3 page in a Node test; Svelte has no runtime test.

```sh
bin/setup
bin/validate
bin/audit
```

`bin/validate` runs behavior, type, lint, workflow and package checks. `bin/audit`
checks dependency advisories and requires network access. See the manifests and
[contribution guide](CONTRIBUTING.md) for the exact tools and commands.

## Runnable demo

Run `bin/demo` after `bin/setup` to start a small Inertia Rails app with React
SSR, a Solid Queue Active Job worker and a shared FileStore cache. Run
`bin/demo verify` for an isolated proof that warming completes and a separate
web process reuses the same native SSR entry. See the
[demo guide](examples/demo/README.md) for commands, configuration and limits.

See [architecture](docs/architecture.md), [source research](docs/grounding.md),
[design comparison](docs/design-comparison.md), the [changelog](CHANGELOG.md) and
the [release procedure](docs/releasing.md).

## License

Inertia Rails SSR Cache uses ShakaCode Trust-Based Commercial Licensing, under
[The Inertia Rails SSR Cache License](LICENSE.md).

TL;DR: development, test, CI, staging and preview use is free for
everyone. Production use is free for organizations under 10 people, $1M
revenue and $1M raised, and for charities, schools and hospitals at any
size. Otherwise, an active ShakaStack Pro subscription (which includes
React on Rails Pro) covers it for organizations under 250 people and
$10M revenue; see [pro.reactonrails.com](https://pro.reactonrails.com/).
Larger organizations and questions:
[contact@shakacode.com](mailto:contact@shakacode.com).

There are no license keys and nothing phones home. [LICENSE.md](LICENSE.md) is the
binding text.
