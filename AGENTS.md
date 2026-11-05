# AGENTS.md

Guidance for coding agents working in this repository.

## Project

`oob-usb-serial` turns a Debian host (typically a Raspberry Pi) into an
out-of-band console box: it discovers USB serial adapters via udev and opens
each one in a window of a single detached tmux session running `tio`. It is
pure bash, shipped as an `Architecture: all` Debian package.

- `src/bin/oob-usb-serial`: CLI (subcommands, user switching, tmux lifecycle)
- `src/lib/discover.sh`: udev discovery, one tab-separated record per adapter
- `src/lib/session-gen.sh`: devices.conf lookup, validation, naming, tio
  command line, tmux config
- `src/etc/`, `src/systemd/`, `src/man/`, `src/completion/`, `src/profile/`:
  installed files (see `Makefile`)
- `debian/`: packaging; `tests/`: bats suite; `docs/wiki/`: user docs

## Commands

```sh
make check     # shellcheck (must pass)
make test      # bats suite: needs bats + tmux; run as a normal user
./build.sh     # build dist/*.deb (Linux/WSL; Docker elsewhere)
```

On Windows, run these in WSL on a copy of the tree on the Linux file system
(permission tests misbehave on `/mnt/c`).

## Targets and compatibility

- Debian 11, 12 and 13 (and Raspberry Pi OS / Ubuntu derived from them).
  CI runs the tests in all three.
- tmux 3.1 is the oldest supported: only use tmux options it has.
- tio 1.x, 2.x and 3.x have different CLIs; version-specific flags go through
  `_oob_tio_log_args`-style helpers keyed on `_oob_tio_version`.
- bats 1.2 (Debian 11) runs the suite: no `run !`, no bats-assert; use the
  `refute` helper in `tests/helpers.bash`.

## Conventions

- Every script uses `set -o errexit -o nounset -o pipefail`.
- Library functions are prefixed `_oob_` (internal) or `oob_` (public).
- Quote anything that reaches a shell command line with `printf %q`.
- Never `eval` data from udev, USB descriptors or config files.
- Tab-separated records are read with `IFS=$'\t' read`, which collapses empty
  fields: keep possibly-empty fields last.
- New behaviour needs a test. System access goes through the test hooks
  (`OOB_SYSFS_ROOT`, `OOB_DEV_ROOT`, `OOB_CONF`, `OOB_DEVICES_CONF`,
  `OOB_RUNTIME_DIR`, `OOB_TMUX_SOCKET`) so tests never touch the real system.
- User-facing changes update the matching page in `docs/wiki/` (published to
  the GitHub wiki by CI), the man page if the CLI changes, and
  `debian/changelog`.

<!-- trail:start -->
## Trail — repo context graph

This repo is indexed in `.trail/cache/`: small linked markdown nodes that explain each
system and carry exact file:line spans, kept in sync with the code through git.

For ANY task here — understanding how something works, finding where code lives,
or scoping a change — get context from the graph before grepping or opening
source files. Re-ask freely (it's cheap) and reuse literal identifiers you
already have (symbol, error string, file name) as the query. New to this repo?
Run `trail map` first — a token-budgeted orientation (dir clusters, hubs,
hotspots), no LLM, no key.

- Run `trail ask "<your question>" --source` → ranked nodes with the relevant
  code spans inlined (each hit's ≤8-line crux by default; `--full` for whole
  definitions when the crux isn't enough). Match the tool to the task shape:
  for understanding or editing, the top node IS the answer — cite its
  `covers:` file:line spans and edit straight from `--source`. For
  exhaustive tasks ("every occurrence / every caller of this pattern"), ranked
  results are top-N, not complete — run `trail grep "<literal>"` instead
  (exhaustive over indexed files, grouped by enclosing symbol), falling back
  to raw `grep -rn` only for unindexed files.
- `trail skeleton <file>` → every definition's signature + span, ~10× cheaper
  than reading the file; use it to skim an API surface.
- `trail callers <symbol>` gives precomputed, exact edges — who calls this.
  Add `--direction out` for what it calls, or `--depth N` to walk
  transitively for the full blast radius. For structural questions, skip
  ranking and use this directly.
- Or browse: `.trail/cache/INDEX.md` lists every node; follow the links.
- Monorepos and folders of multiple repos rank fairly across sub-projects —
  hits carry `[scope/]` labels naming which one they're from. Narrow with
  `trail ask "<task>" --in <scope>/` once you know where you're working.

If a returned span is truncated ("+N more lines"), open the file at that exact
range before finalizing. Only open source files when a node genuinely lacks a
needed detail, and then at the exact file:line the node points to — never
re-read whole files.

After big code changes, refresh the graph with `trail build` (deterministic,
no API key, $0).
<!-- trail:end -->
