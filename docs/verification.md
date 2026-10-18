# Bootstrap verification

The runtime and toolchain at `9b766ec3d0a44a8304d4e32a55e56b33563a194e` passed `bin/validate`:
94 Ruby examples, seven Node tests, RuboCop, RBS/Steep,
strict TypeScript/ESLint, formatting, Markdown lint, Knip, ShellCheck, actionlint,
Zizmor and Gitleaks. Both built artifacts passed package checks and isolated
consumer loading. The Ruby examples comprise 66 unit, four tooling and 24 real
integration cases. The public facade and pure domain receive Steep implementation checking;
dynamic Rails/Rack adapters receive runtime coverage.

All 24 integration examples, 18 cache-observer examples and six job unit examples also passed the lower
dependency lock: Rails 7.2.4 and JSON 2.21.2.
Local runs used Ruby 3.4.6 and Node 24.8.0. CI also
exercises Ruby 3.3 and Node 22; local results do not establish those runtime results.
`bin/audit` passed for both Ruby locks and npm with no advisory severity excluded.
Audit results are a point-in-time observation, not a lasting guarantee.

The integration fixture boots released Inertia Rails 3.22.0 with real Inertia
React SSR. A warming process and a separate visitor process share FileStore.
Tests assert SSR HTML/head, native cache evidence and renderer invocation counts.
They cover version changes and rollback, wrong Node builds, unavailable/failed
SSR, cached null/false values, disabled/nonretaining caches, unstable props,
redirects, protected routes, late HTTP failures, missing bundles and cookie isolation.
Serialized `ActiveJob::Base.execute` checks prove that successful requests and
propagated controller exceptions preserve the surrounding job's executor and
CurrentAttributes until its single normal completion. Each request sees fresh
CurrentAttributes. The isolated Corepack tests cover a missing, wrong-version,
failing or matching pnpm executable. FileStore boundary tests prove conservative
failure for split long keys and subclasses even when native caching succeeds.
A separate real-boot control proves application Active Job initializers are honored.
Controlled parent exceptions and termination prove the request thread finishes
every executor cleanup callback before the parent unwinds; a failing child cannot
replace the original parent interruption. Three initialized-app cases prove
that reload-enabled or explicitly serialized execution is rejected before
enqueueing or creating request threads, while the supported environment still
executes the full middleware stack. Real cache-store regressions prove malformed
UTF-8 and split multibyte keys cannot interrupt unrelated cache hits. A real
controller parses the fixed synthetic address through `request.remote_ip` and
`IPAddr` while retaining native SSR reuse.

## Synthetic comparison

Run `bin/benchmark 30` after `bin/setup` and `pnpm build`. The recorded
[raw samples](benchmark.json) identify the exact runtime revision and environment.
The recorder adds source revision, command and timestamp metadata to the command's
JSON output; timing samples and renderer counts are unmodified.
The captured command output matches the committed data exactly after removing
those metadata fields. On this macOS host, observed nonzero monotonic clock
increments were approximately 0.001 ms, so four-place rounding can serialize as
three decimal places without any postprocessing.
Both conditions use the same `/stable` route, props and build: the control disables
native SSR caching; the experiment warms and enables it. The initial repository
contained no implementation, so it cannot provide an executable baseline.

| Condition                 | Timed requests | Warmup requests | Node renders | p50 (ms) | p95 (ms) |
| ------------------------- | -------------- | --------------- | ------------ | -------- | -------- |
| Native SSR cache disabled | 30             | 5               | 35           | 2.028    | 5.568    |
| Warmed native SSR cache   | 30             | 5               | 0            | 0.639    | 1.513    |

The warming job itself caused one Node render and verified reuse. The timed
visitor block ran in a separate Rails process. Blocks ran sequentially, uncached
then cached, at concurrency one, with other task tests stopped. These are small
local samples on a shared machine, not an isolated or randomized performance study.
There is no artificial renderer delay, database workload or production traffic.
The strongest result is elimination of repeated Node renders in this fixture;
the latency figures cannot predict an application's production benefit.

An adopter pilot should test representative anonymous props, its shared cache
backend, queue capacity and deployment readiness. Native SSR hits still execute
controllers and resolve props. Database-cache performance is outside this package.
