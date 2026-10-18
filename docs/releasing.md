# Releasing

Both packages ship together at the same version: the `inertia_rails_ssr_cache` gem
on RubyGems and the `inertia-rails-ssr-cache` npm package. Version 0.1.0 is the
first public release. No CI job publishes; a maintainer publishes by hand with
registry MFA.

## Adopter pilot before production use

A registry release does not establish production readiness in your application. Before
enabling warming in a production application, its maintainer must run a pilot
with representative anonymous routes and the actual worker/web cache topology:

- Confirm stable props and Inertia versions across fresh requests, including real
  client addresses and browsers. Exclude routes whose props vary by IP, geolocation
  or browser identity. Verify native
  reuse from a separate web process, with matching SSR body/head and build identity.
- Measure controller/query load and request latency with and without warming.
  Choose route count and queue concurrency from the application's capacity budget;
  the synthetic fixture cannot supply those limits.
- Size the database pool for request threads as well as job callbacks that hold
  a connection while waiting. Confirm the intended backend's execution lifecycle
  and application callbacks with real jobs.
- Verify deployment readiness, failures, retry behavior and rollback with the
  intended Active Job backend. Exercise cache expiry/eviction and a mismatched
  SSR bundle, and confirm operators can observe failed jobs.

Record the tested application revision, cache backend, route variants and measured
results. Enable only the validated route set; keep warming disabled when parity
or capacity is unverified. This pilot is a prerequisite for production use, not
evidence supplied by this repository's unit tests or a registry release.

## Registry release

The gem version file, `lib/inertia_rails_ssr_cache/version.rb`, is the one place
to change the version. The package check fails unless both npm manifests match
it. Ruby and npm prerelease syntax differs: map `0.1.0.rc.1` to `0.1.0-rc.1`
explicitly rather than updating one artifact alone.

1. On a branch, bump the version file and both `package.json` versions, add the
   [changelog](../CHANGELOG.md) entry, and merge the PR.
2. In a clean checkout of the merged commit, run `bin/setup`, `bin/validate` and
   `bin/audit`. A network failure in `bin/audit` is an incomplete audit, not a
   pass.
3. Run `bin/package`. It writes
   `tmp/packages/inertia_rails_ssr_cache-VERSION.gem` and
   `tmp/packages/inertia-rails-ssr-cache-VERSION.tgz`, and smoke-tests both from
   a clean consumer.
4. Inspect both artifacts: `gem specification FILE files` for the gem and
   `tar -tzf FILE` for the npm tarball. Only `lib/`, `sig/`, `README.md` and
   `LICENSE.md` ship in the gem; only `dist/`, `README.md`, `LICENSE.md` and
   `package.json` in the npm package. Record both SHA-256 checksums.
5. Check that the target versions are not already on either registry:
   `gem info inertia_rails_ssr_cache --remote --all` and
   `npm view inertia-rails-ssr-cache versions`.
6. Tag the commit `vVERSION` locally.
7. Push the gem: `gem push tmp/packages/inertia_rails_ssr_cache-VERSION.gem`.
8. Publish npm:
   `npm publish tmp/packages/inertia-rails-ssr-cache-VERSION.tgz --access public`.
9. Verify both registries: `gem info inertia_rails_ssr_cache --remote` and
   `npm view inertia-rails-ssr-cache version license`.
10. Push the tag and create the GitHub release from the changelog entry.

Publishing two artifacts is not an atomic operation. If one publish fails, check
which versions exist on each registry before retrying anything; never republish
a version number that already exists on either registry.
