# Architecture: bounded Active Job warming through Rack

## Problem

Inertia Rails 3.22 owns SSR serialization and caching. A useful warmer must run
ordinary requests and prove reuse without taking ownership of those internals.
HTTP 200 can mean client-rendering fallback; even a native cache hit can contain
an invalid SSR value. Queued work can also cross release boundaries.

## Usage (caller's view)

The application registers an origin and up to 50 public paths at boot, configures
a shared retaining Inertia cache and stable release version, and calls
`InertiaRailsSsrCache.warm_later`. It receives an Active Job ID. The Rails task
`inertia_rails_ssr_cache:warm` invokes the same entry point.

The SSR bundle wraps its existing render callback with
`guardRelease(buildRelease, render)`. That token is embedded at build time and
matches the configured Inertia version. The wrapper rejects a mismatch before
rendering and preserves the callback's synchronous result or original promise.
See [application setup](../README.md#application-setup) for the complete call sites.

Operational consumers subscribe to `target.inertia_rails_ssr_cache` and
`warm.inertia_rails_ssr_cache`. Results contain public target/outcome metadata;
`WarmFailed#report` exposes a failed run. Enqueueing is not completion, and a
completed run is not a lasting guarantee of cache coverage.

## Shape

The initial sketch compared in-process Rack requests with release-pinned HTTP
requests before implementation. The final module boundaries are:

| Module                                  | Owned knowledge                                                                                               |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Public Ruby entry point                 | Boot-time registration, enqueueing and current Inertia release                                                |
| `Configuration`                         | Origin/path eligibility, immutable target snapshot, execution-time registration checks                        |
| `WarmJob`                               | One sequential bounded run, intended-release check, outcomes and notifications                                |
| `Probe`                                 | Fresh Rack environment, request-local cache observations, native cache identity and retained-value validation |
| `Observation`, `TargetResult`, `Report` | Pure interpretation of evidence and success/failure                                                           |
| Railtie                                 | Rails task registration                                                                                       |
| npm `guardRelease`                      | Build/page version agreement before invoking the existing SSR callback                                        |

The public flow is configure → enqueue. Execution is job → probe → ordinary Rails
application. There is no alternate transport, scheduler, run database, lease,
completion callback tree or direct cache-writing API. Inertia alone writes SSR
entries. The interface hides request construction and proof details while leaving
public-route eligibility, deployment readiness and queue capacity with the app.

At enqueue time the registered paths, origin and evaluated Inertia version become
primitive Active Job arguments. At execution the targets must still be registered
and the current release must match. Versions must resolve to the same stable
value in the job process and controller; context-dependent versions are outside
the initial contract. Validation uses the public Inertia configuration API.

Each probe creates a new Rack request with an explicit Host and HTML Accept
header. It retains the full middleware stack, supplies no credentials or cookie
jar, omits Inertia visit headers, and does not follow redirects. `REMOTE_ADDR` is
`192.0.2.1`, a [documentation address](https://www.rfc-editor.org/info/rfc5737/)
used only as synthetic Rack metadata; no User-Agent is supplied. This lets normal
IP-parsing middleware operate, but routes with IP-, geolocation- or browser-dependent
props are outside the initial contract. Notifications
are attributed to the calling thread **and fiber**, with subscription cleanup on
failure. The observer keeps native-key knowledge in one module instead of
reconstructing the page or digest throughout the gem.

Each request runs in a fresh joined thread. Calling Rails' executor middleware
on the job's own thread completes its active executor prematurely, clearing job
CurrentAttributes and running connection cleanup. A separate request thread owns
its own executor and observer without copying the job's execution state. Joining
permits concurrent dependency loading for Rails 7.2 and propagates the original
request exception. Requests remain sequential; only one extra thread is active
per job. A job callback retaining a database connection can require another
connection for the request, so pool sizing belongs in the adopter pilot.

The job owns that request thread until it finishes. If a host interrupts the job
while it waits, cleanup drains the request before the interruption propagates;
the warmer does not inject an asynchronous exception into Rails request cleanup.
This can delay job shutdown for the remaining request duration and supplies no
hard deadline. The job class loads lazily so requiring the gem during Rails boot
does not force Active Job configuration hooks ahead of application initializers.

Warming requires a Rails environment with code reloading disabled and concurrency
not explicitly disabled. Actual watched-file changes reproduced an unload-lock
cycle between a waiting job and its request; `allow_concurrency = false` also
reproduced a cycle through Rails' executor monitor. Both cases were confirmed on
Rails 7.2 and 8.1 with bounded subprocesses. Enqueueing and execution reject these
configurations before dispatching a request. We keep the full middleware stack
and fail clearly instead of manipulating Rails' private reload state.

A target succeeds only when:

1. Both fresh requests return HTTP 200 HTML.
2. Each request observes exactly one native SSR cache fetch.
3. Both refer to the same cache identity and the second is a hit.
4. The retained native value has an SSR response shape: a string body and an
   array of string head entries.

The fourth condition was added after a real failing test: an HTTP 200 SSR server
response containing JSON `null` was cached, then produced client rendering on a
native hit. The probe uses the cache store's public read API, preserving observed
namespace/version options. FileStore's encoded notification keys also required a
store-specific compatibility path, proven with namespaced stores. Unknown or
ambiguous evidence fails verification; the gem does not patch renderer methods.
Namespace support is limited to absent or static string values. Callable namespaces
are unverifiable. FileStore recovery supports the exact built-in class and an
encoded key that fits in one filename. Split long keys and subclasses are
unsupported; missing or ambiguous identity evidence fails closed. Invalid string
encodings and unparseable notification keys provide no native evidence without
interrupting unrelated application cache operations.

## Synthesis decision

The owner and independent artifact judge selected the Rack design: 22/25 versus
18/25 for HTTP. Both design agents and the judge used the inherited host model,
so this was independent design exploration rather than cross-provider review.
See [the comparison](design-comparison.md) for the rubric and tradeoffs.

The HTTP candidate contributed precise failure outcomes, strict target validation
and the warning that cache hits bypass a JavaScript callback guard. Its signed
request/response protocol, observer middleware and extra routing configuration
were rejected for the first version. No second transport was retained.

The first Rack spike established the request/cache seam. Implementation then
replaced the sketch with actual package APIs and a Rails/Inertia/React fixture.
The null-response regression refined what counts as evidence; it did not require
a new cache owner or remote diagnostic interface.

## Tradeoffs accepted

- We accept at most 50 paths per job and sequential requests in exchange for
  portable bounded fan-out and no distributed state machine.
- We accept two ordinary GETs per target in exchange for detecting unstable page
  data, failed retention and normal client-rendering fallback.
- We accept worker-process rendering in exchange for deterministic Rails release
  selection and direct cache evidence. Worker/web configuration and cache
  topology must agree.
- We accept a narrow Inertia Rails 3.22 compatibility contract in exchange for
  honest evidence on released APIs. Upstream development-only notifications and
  timeout options are not used.
- We accept a conservative failure if cache entries expire or disappear during
  verification. A past success never prevents deliberate rewarming.

## Alternatives considered

**Release-pinned HTTP:** exercises the deployed web tier but needs trusted cache
observations and release identity in its response. Signing and observer middleware
add substantial surface before basic warming can be verified. Reconsider when an
adopter specifically needs that deployment boundary.

**Direct SSRRenderer invocation:** requires exact page data and bypasses the
normal controller/shared-prop path. It exposes adapter serialization details to
callers and weakens visitor parity.

**Distributed per-page jobs:** can handle larger route sets but needs explicit
completion, cancellation, retry and ownership semantics. Introduce it only with
a measured requirement and backend-independent evidence.

## Open questions and risks

Will the first adopter's public page props remain stable across real anonymous
requests? Can its workers and web processes share the same retaining cache and
configuration? What queue capacity and route-set size fit its database budget?
These are deployment-specific validation tasks, not guarantees inferred from the
synthetic fixture.

The npm guard executes only on misses. It cannot certify preexisting entries from
an unguarded or corrupted renderer. Begin with a fresh immutable release token
when adopting it. Native SSR reuse still executes Rails controllers and props;
no database-cache speedup is claimed.

Active Job does not promise fleet-wide concurrency or uniqueness. Multiple jobs
can overlap. Route count is bounded, but there is no hard end-to-end deadline or
asynchronous Ruby timeout around requests. Readiness, cutover and retry policy
remain with the host.

## Verification and next implementation step

The repository's integration suite uses released Inertia Rails, real React SSR
and FileStore shared between separate Rails processes. It checks ordinary visitor
reuse, release changes/rollback, cookie isolation and false-positive cases. The
pure Ruby domain is checked with RBS/Steep and the npm API with strict TypeScript;
framework boundaries have runtime integration coverage.

The next expansion should be an adopter-specific pilot with representative public
props and a production-style shared cache, before adding larger-run orchestration.
