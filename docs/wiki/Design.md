# Design

`oob-usb-serial` is a thin orchestration layer over two established tools:

- **tio**, the serial terminal. One tio per adapter handles baud rate and
  framing, logging and, crucially for an out-of-band box, **automatic
  reconnection** when a device disappears and comes back.
- **tmux**, the multiplexer. One detached session holds one **window per
  adapter** (window name = console name), so every console is reachable and
  switchable over a single SSH connection.

```
udev discovery ──► resolve each adapter against devices.conf
               ──► tmux new-session / new-window per adapter
               ──► each window runs: tio <flags> <stable /dev/serial path>
```

## Code layout

| File | Role |
|------|------|
| `src/lib/discover.sh` | Finds USB tty devices via udev, prints one record per adapter |
| `src/lib/session-gen.sh` | `devices.conf` lookup, validation, naming, target choice, tio command line, tmux config |
| `src/bin/oob-usb-serial` | CLI: subcommands, user switching, the tmux session lifecycle |

## Discovery

`oob_discover_raw` walks the USB devices in sysfs, asks udev for each
`…/tty/<name>` node's properties and keeps the nodes whose udev `SUBSYSTEM`
is `tty` and that have an `ID_SERIAL`. USB disks, HID devices, webcams and
other USB nodes are skipped even though they also carry an `ID_SERIAL`.

udev properties are read as plain `KEY=VALUE` text and are **never evaluated**
by the shell: their values come from USB descriptors, i.e. from whatever
device is plugged in.

Each record has six tab-separated fields (`oob-usb-serial discover`):

```
<devnode>  <id_serial>  <vendor>  <model>  <by-id>  <by-path>
```

`<by-id>` falls back to `<devnode>` when no `/dev/serial/by-id` link exists;
`<by-path>` is empty when no `/dev/serial/by-path` link exists.

## Stable device identity

`/dev/ttyUSBx` numbers change across reboots and replugs, so they are never
used for identity:

1. **Matching**: `devices.conf` is keyed on `ID_SERIAL` (and optionally the
   by-path port), so a mapping follows the same adapter.
2. **Connection**: tio opens a `/dev/serial/*` symlink, never `ttyUSBx`, so
   its reconnect re-attaches to the right device after a replug:
   - `by-id` normally: it follows the adapter wherever it is plugged in;
   - `by-path` when several attached adapters report the same `ID_SERIAL`.
     Identical adapters would share (and fight over) one by-id link; by-path
     names the physical port, which is unique;
   - the plain device node only when neither link exists.

## Resolution

`oob_resolve` turns discovery records into session records: it applies the
first matching `devices.conf` section (or the global defaults and an automatic
name), validates every serial setting (invalid values fall back to the default
with a warning), sanitizes window names to `[A-Za-z0-9_.-]`, makes them unique
(`-2`, `-3`, …) and picks the device path tio opens. `list` and `start` both
use it, so what `list` shows is what `start` runs.

## The tmux session

- **One server, one owner.** The session lives on a dedicated socket
  (`tmux -L oob`) owned by `OOB_USER`. `tmux -L` sockets are per-user, so a
  session command run as another user would talk to a different server. The
  CLI therefore runs session commands only as `OOB_USER`: as root it switches
  (`runuser`, falling back to `sudo -u`); as anyone else it refuses.
- **Generated tmux config** (not the user's `~/.tmux.conf`), limited to
  options available in tmux 3.1:
  - `remain-on-exit on`: a console whose tio exits stays visible with its exit
    status instead of vanishing;
  - `Ctrl-b R` bound to `respawn-window` to relaunch one console in place;
  - status line, mouse mode, a 10 000-line scrollback.
- **Runtime directory.** The config is written to `/run/oob-usb-serial`, which
  root creates for `OOB_USER` before switching user. Existing paths are never
  re-owned. When that directory is not usable (e.g. `OOB_USER` started the
  session without root), a private `mktemp -d` directory is used and removed
  once tmux has read the file. Nothing is written to a predictable path in
  `/tmp`.

## tio versions

The logging flags changed across tio releases, so `oob-usb-serial` reads
`tio --version` once per start:

| tio | `-l` means | Logging flags used |
|-----|-----------|--------------------|
| 1.x | `--log <file>` | `-l <file>` |
| 2.0 – 2.5 | `--log` (no argument) | `--log --log-file <file>` |
| 2.6+ / 3.x | `--log` (2.x), `--list` (3.x) | `--log --log-file <file> --log-append` |

An unreadable version gets `--log --log-file`, which every 2.x and 3.x
release accepts. The serial flags (`-b -d -p -s -f`) are the same in every
version; `parity` is limited to `none`/`odd`/`even` because Debian 11's tio
has no mark/space parity.

## systemd service

The unit runs `oob-usb-serial start` as **root** (no `User=`): the script
then follows `OOB_USER` from the config, prepares its directories and drops
privileges. This keeps one source of truth for the session user. It is
`Type=forking`: the tmux server outlives the start command and becomes the
service's main process.

It is ordered after udev's coldplug (`systemd-udev-trigger.service`) instead
of the deprecated `systemd-udev-settle.service`. Adapters that enumerate
later make the first start fail; `Restart=on-failure` retries every 15 s, at
most 10 times in 5 minutes.

## Packaging and upgrades

The package is `Architecture: all` and built with `xz` compression so older
`dpkg` (Debian 11, older Raspberry Pi OS) can install it.

Both config files are dpkg **conffiles**. On upgrade, dpkg:

- replaces a file you never edited with the packaged version;
- keeps your file if you edited it and the packaged version is unchanged;
- **prompts** (keep / take maintainer's / diff / shell) if both changed. It
  never silently overwrites your edits.

`postinst` reads `OOB_USER` from the config (as text, it does not source the
file as root), creates that system user if missing and adds it to `dialout`.

## Out of scope

- **Hotplug**: adapters plugged in after the session started appear on
  `restart`. Adding windows from a udev rule is a possible future feature.
- **Versions before 2.0.0** used GNU `screen` and an stty-style
  `framing = cs8,-parenb,…` key. 2.0.0 moved to tio + tmux with separate
  `data`/`parity`/`stop`/`flow` keys. A leftover `framing` key is ignored and
  that device uses the global defaults.
