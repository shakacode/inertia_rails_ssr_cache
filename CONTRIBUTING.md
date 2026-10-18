# Contributing

Work on a feature branch and open a pull request against `main`.

## Licensing and contributions

Inertia Rails SSR Cache is distributed under The Inertia Rails SSR Cache License
(see [LICENSE.md](LICENSE.md)). Before we can merge your contribution, we need you
to agree to our Contributor License Agreement (see [CLA.md](CLA.md)).

We use a sign-off model. Add a Signed-off-by line to each commit:

```sh
git commit -s -m "Your message"
```

The sign-off certifies that you have read and agree to [CLA.md](CLA.md), including
the clause covering AI-assisted contributions: you are responsible for any code you
submit regardless of the tools used to produce it.

## Development

Run `bin/setup`, then `bin/validate` and `bin/audit`. The validation command is the
local counterpart of CI: Ruby behavior and types, strict TypeScript and lint,
formatting, dead-code checks, workflow checks, and gem/npm artifact validation.
Check current runtime and tool versions in the manifests and lockfiles.

Changes to caching must retain the real Rails/Inertia/React integration test.
A warm request must populate the native cache and a separate visitor process
must reuse it. Include negative cases when changing request or release behavior.

Read [architecture](docs/architecture.md) before adding a new runtime abstraction.
Keep public APIs small, preserve the ordinary Rails request path, and distinguish
portable Active Job behavior from backend-specific queue guarantees.

Releases follow [the release procedure](docs/releasing.md).
