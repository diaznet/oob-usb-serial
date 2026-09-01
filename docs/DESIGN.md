# oob-usb-serial — design & reference

Detailed documentation that would clutter the README. Covers architecture, the
full configuration reference, and packaging/upgrade behaviour.

## Architecture

`oob-usb-serial` is a thin orchestration layer over two well-established tools:

- **`tio`** — the serial terminal client. One `tio` process per adapter handles
  baud rate and framing (data bits, parity, stop bits, flow control), logging,
  and — crucially for an out-of-band box — **automatic reconnection** when a
  device disappears and reappears.
- **`tmux`** — the multiplexer. A single detached session holds one **window
  per adapter** (window name = the console's friendly name), so the whole set
  of consoles is reachable and switchable over one SSH connection.

Flow:

```
discover adapters (udev) ─▶ resolve each against devices.conf
                          ─▶ tmux new-session / new-window per adapter
                          ─▶ each window runs: tio <flags> <by-id path>
```

### Stable device identity

Two stability layers, both deliberately avoiding `/dev/ttyUSBx` (whose number
can change across reboots and replugs):

1. **Matching** — config is keyed on the adapter's udev `ID_SERIAL`, so a
   console mapping always follows the same physical adapter.
2. **Connection** — `tio` is launched on the adapter's `/dev/serial/by-id/*`
   symlink, not the `ttyUSBx` node. That symlink follows the physical device,
   so tio's auto-reconnect re-attaches to the correct adapter after a replug.
   (If an adapter has no by-id symlink — rare, e.g. no serial number — the tool
   falls back to the `ttyUSBx` node.)

### tmux session specifics

- The session runs on a **dedicated socket** (`tmux -L oob`) so the systemd
  service and an interactive SSH login unambiguously share the same server,
  regardless of `$TMUX_TMPDIR` differences between environments.
- A generated tmux config (not the user's `~/.tmux.conf`) sets:
  - `remain-on-exit on` — a console whose `tio` exits leaves a visible dead
    window with its exit status instead of silently vanishing.
  - `Ctrl-b R` bound to `respawn-window` — relaunch a single closed console in
    place without tearing down the session.
  - a status line, mouse mode, and a scrollback buffer.

## Configuration reference

### Global — `/etc/oob-usb-serial/oob-usb-serial.conf`

Sourced as shell (`KEY="value"`). Defaults applied to any adapter not matched
in `devices.conf`:

| Variable | Meaning | Default |
|----------|---------|---------|
| `OOB_DEFAULT_BAUD` | baud rate | `115200` |
| `OOB_DEFAULT_DATA` | data bits (5–8) | `8` |
| `OOB_DEFAULT_PARITY` | `none` / `odd` / `even` | `none` |
| `OOB_DEFAULT_STOP` | stop bits (1 or 2) | `1` |
| `OOB_DEFAULT_FLOW` | `none` / `soft` / `hard` | `none` |
| `OOB_SESSION_NAME` | tmux session name | `oob` |
| `OOB_LOG_DIR` | per-console log dir (empty = off) | *(empty)* |
| `OOB_USER` | account for the boot service + login attach | `oob` |

When `OOB_LOG_DIR` is set, each console logs to `<dir>/<name>.log` via `tio -l`.
Log rotation is the operator's responsibility.

### Per-device — `/etc/oob-usb-serial/devices.conf`

INI. Each `[section]` defines one device; the **section name is the tmux window
title**. Keys:

| Key | Meaning | Required |
|-----|---------|----------|
| `match` | shell glob matched against udev `ID_SERIAL` | yes |
| `baud` | baud rate | no → `OOB_DEFAULT_BAUD` |
| `data` | data bits 5/6/7/8 | no → `OOB_DEFAULT_DATA` |
| `parity` | `none` / `odd` / `even` | no → `OOB_DEFAULT_PARITY` |
| `stop` | stop bits 1/2 | no → `OOB_DEFAULT_STOP` |
| `flow` | `none` / `soft` / `hard` | no → `OOB_DEFAULT_FLOW` |

Values use `tio`'s own vocabulary. `parity` supports only `none`/`odd`/`even`
(the `tio` shipped with Debian 11 does not support mark/space parity). Sections
are matched in file order; the first whose `match` glob fits an adapter wins.
Unknown keys are ignored. Comments start with `#` or `;`. An empty file means
every adapter opens at the global defaults.

Example: **115200 8N1, no flow control**

```ini
[core-switch]
match  = *FT232R*_A5069RR4
baud   = 115200
data   = 8
parity = none
stop   = 1
flow   = none
```

## Discovery record format

`oob-usb-serial discover` prints one tab-separated record per adapter:

```
<devnode>\t<id_serial>\t<vendor>\t<model>\t<by-id-path>
```

`list` renders this as a table; scripts can consume `discover` directly.

## Packaging & upgrades

The package is `Architecture: all` (pure shell) and built with `xz`
compression so it installs on older `dpkg` (Debian 11+, older Raspberry Pi OS).

Both config files are registered as dpkg **conffiles**. On upgrade, dpkg:

- replaces a file you never edited with the packaged version;
- keeps your file if you edited it and the packaged version is unchanged;
- **prompts** you (keep / take maintainer's / diff / shell) if you edited it and
  the packaged version also changed — it never silently overwrites your edits.
  Your original is preserved as `.dpkg-old`/`.dpkg-dist` in the conflict case.

The `oob` user is created at install (`postinst`) and added to the `dialout`
group so it can open serial devices; human users must join `dialout` themselves.

## Relationship to versions before 2.0.0

Versions 1.x used GNU `screen` and an `stty`-style `framing = cs8,-parenb,...`
config key. 2.0.0 switched to `tio` + `tmux` and replaced `framing` with the
per-parameter `data`/`parity`/`stop`/`flow` keys. There is no automatic
migration: a leftover `framing` key is simply ignored and the device uses the
global defaults.
