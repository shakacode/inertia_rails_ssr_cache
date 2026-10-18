# Inertia Rails SSR cache demo

A small Rails app with React SSR, a Solid Queue Active Job worker backed by
SQLite, and a FileStore cache shared by separate worker and web processes on
one host. The library itself remains independent of Solid Queue.

## Run it

From the repository root, using the [development prerequisites](../../README.md#development):

```sh
bin/setup
bin/demo
```

The launcher builds the JavaScript, prepares the queue database, starts the
Node SSR server, Puma and Solid Queue, then enqueues and waits for the initial
warm job. Open <http://127.0.0.1:3300>. Press Ctrl-C in the launcher to stop its
processes. No package publication or external services are needed.

Click **Hydration clicks: 0** to verify browser hydration. The counter is local
React state; the workflow cards describe the experiment and display no live
cache status. To enqueue and wait for another job while the demo is running:

```sh
bin/demo warm
```

## Verify the complete path

```sh
bin/demo verify
```

Verification creates a unique temporary runtime directory, empty cache and
SQLite queue, and uses available local ports. It checks that the enqueued job
is pending before the worker starts, then completes through Solid Queue. The
worker must observe a native SSR cache miss followed by a hit. Two real HTTP
requests through a separate Puma process must hit that same entry and receive
the expected SSR body, head and release identity, with exactly one Node render.
The command prints a JSON proof, stops its processes and removes its temporary
runtime directory; any failed check exits unsuccessfully.

## Configuration and evidence

| Variable        | Default    | Meaning                                      |
| --------------- | ---------- | -------------------------------------------- |
| `DEMO_RUNTIME`  | `tmp/demo` | Use an absolute path for a separate runtime. |
| `DEMO_WEB_PORT` | `3300`     | Puma port on `127.0.0.1`.                    |
| `DEMO_SSR_PORT` | `13373`    | Node SSR port on `127.0.0.1`.                |
| `APP_RELEASE`   | `demo-v1`  | Rails version and embedded JavaScript token. |

Use the same environment for `bin/demo` and `bin/demo warm`. Restart the demo
after changing `APP_RELEASE` so both bundles are rebuilt. The normal runtime
holds `queue.sqlite3`, `cache/`, built assets, process logs, `events.jsonl` cache
and job evidence, and `renders.jsonl` SSR calls. Rails reloading is disabled.

This is a local-only app with a fixed demo secret and synthetic public props;
do not deploy it or use real data. Shared FileStore proves reuse across processes
on one filesystem, not a distributed production cache. SSR hits still execute
controllers and prop construction. This controlled example does not replace the
[adopter pilot](../../docs/releasing.md#adopter-pilot-before-production-use) with
real route variants, deployment topology and measured database capacity.
