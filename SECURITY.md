# Security

Please do not open a public issue for a suspected vulnerability. Use GitHub's
**Report a vulnerability** button on this repository. If you cannot use GitHub,
email [contact@shakacode.com](mailto:contact@shakacode.com) with the subject line
`Inertia Rails SSR Cache security`.

Include the affected package (`inertia_rails_ssr_cache` gem or
`inertia-rails-ssr-cache` npm package) and version, a minimal synthetic
reproduction, and the relevant request/cache behavior. Exclude customer data,
credentials and production page payloads.

Fixes land on the latest released version.

Warming targets must be explicitly approved public GET routes. The application
retains its authorization and middleware; the warmer supplies no credentials and
does not follow redirects. Public routes may still perform expensive work or
write application data: route eligibility remains an application decision.

Use matching immutable Rails and JavaScript build identities, and a cache store
shared by worker and web processes. See [architecture](docs/architecture.md) for
what observed cache reuse proves and its limitations.
