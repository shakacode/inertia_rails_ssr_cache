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

Releases run through one Rake task, like the other ShakaStack gems. Unlike
Shakapacker's task, it never bumps versions or commits to `main`: the version
bump is an ordinary PR.

1. On a branch, set the version in `lib/inertia_rails_ssr_cache/version.rb` and
   both `package.json` files, and add a dated `CHANGELOG.md` section
   (`## 0.2.0 — 2026-11-01`). Ruby and npm prerelease syntax differs: the task
   maps `0.2.0.rc.1` to `0.2.0-rc.1`, and the npm files must use the npm form.
   Merge the PR.
2. On an up-to-date `main`, dry-run the release:

   ```sh
   bundle exec rake "release[,true]"
   ```

3. Release:

   ```sh
   bundle exec rake "release[0.2.0]"
   ```

The task:

- stops unless you are on a clean `main` equal to `origin/main`, the version
  files and a dated changelog section match the version, `gh`, npm and RubyGems
  credentials are present, and CI passed on `HEAD`;
- runs `bin/setup`, `bin/validate` and `bin/audit` in a detached worktree of
  `HEAD`, and prints both artifacts with their checksums;
- refuses to continue if either registry already holds that version with
  different contents;
- asks you to type the version, then tags `HEAD` as `vVERSION`;
- runs `gem push` and `npm publish` (prereleases use the `next` dist-tag), each
  asking for your one-time password;
- waits until both registries serve the built contents, pushes the tag and
  creates the GitHub release from the changelog section.

Publishing two artifacts is not atomic. If a run stops partway, rerun the same
command: a registry that already serves identical bytes is skipped, and an
existing local tag is reused only if it points at `HEAD`. To recreate only the
GitHub release, run `bundle exec rake "sync_github_release[0.2.0]"`.
