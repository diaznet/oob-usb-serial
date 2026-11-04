# Configuration

Two files, both under `/etc/oob-usb-serial/` and both dpkg conffiles (your
edits survive upgrades). Changes apply on the next `oob-usb-serial restart`.

## Global: `oob-usb-serial.conf`

Shell syntax (`KEY="value"`). The defaults apply to every adapter that has no
section in `devices.conf`.

| Variable | Meaning | Default |
|----------|---------|---------|
| `OOB_DEFAULT_BAUD` | baud rate | `115200` |
| `OOB_DEFAULT_DATA` | data bits: 5, 6, 7 or 8 | `8` |
| `OOB_DEFAULT_PARITY` | `none`, `odd` or `even` | `none` |
| `OOB_DEFAULT_STOP` | stop bits: 1 or 2 | `1` |
| `OOB_DEFAULT_FLOW` | `none`, `soft` (XON/XOFF) or `hard` (RTS/CTS) | `none` |
| `OOB_SESSION_NAME` | tmux session name | `oob` |
| `OOB_LOG_DIR` | per-console log directory; empty = no logging | *(empty)* |
| `OOB_USER` | account that owns the session | `oob` |

### Changing `OOB_USER`

Set the new name in the file, then:

```sh
sudo dpkg-reconfigure oob-usb-serial   # creates the user, adds it to dialout
sudo systemctl restart oob-usb-serial
```

The boot service always follows `OOB_USER`; there is no `User=` to edit in
the unit (see [[Boot and Login|Boot-and-Login]]).

## Per-device: `devices.conf`

INI format. Each `[section]` is one adapter, and the section name is its tmux
window title (letters, digits, `.`, `_` and `-`; anything else becomes `_`).

| Key | Meaning |
|-----|---------|
| `match` | shell glob matched against the adapter's udev `ID_SERIAL` |
| `path` | shell glob matched against its `/dev/serial/by-path` link (full path or basename): the physical USB port |
| `baud` | baud rate |
| `data` | data bits: 5, 6, 7 or 8 |
| `parity` | `none`, `odd` or `even` |
| `stop` | stop bits: 1 or 2 |
| `flow` | `none`, `soft` or `hard` |

Rules:

- A section needs `match`, `path`, or both. With both, both must fit.
- Sections are tried in file order; the first one that fits wins.
- Omitted keys use the global defaults. Invalid values are reported when the
  session starts and replaced by the defaults.
- Comments start with `#` or `;`; unknown keys are ignored.
- An empty file is fine: every adapter then opens at the defaults, with an
  automatic name.

Find the `ID_SERIAL` of your adapters with `oob-usb-serial list`, or let
`sudo oob-usb-serial config` write the sections for you.

Example, a switch console at 9600 8N1:

```ini
[core-switch]
match  = *FT232R*_A5069RR4
baud   = 9600
data   = 8
parity = none
stop   = 1
flow   = none
```

If two sections would produce the same window name, the later ones get `-2`,
`-3`, … appended.

## Identical adapters

Adapters are normally told apart by `ID_SERIAL`, which includes the chip's
serial number. Two kinds of setup report the **same** `ID_SERIAL` for
different consoles:

- cheap adapters without a serial number (many CH340 and PL2303 clones), and
- the ports of a multi-port adapter (FT2232, FT4232, …).

For those, `oob-usb-serial`:

- connects tio through `/dev/serial/by-path/…` (the physical USB port) instead
  of `/dev/serial/by-id/…`, which identical clones would share;
- names unmapped ones by port (`…_1.2_1.0`, `…_1.3_1.0`);
- writes a `path` key from `config`, so each port gets its own section:

```ini
[rack-a]
match  = 1a86_USB_Serial
path   = platform-3f980000.usb-usb-0:1.2:1.0-port0

[rack-b]
match  = 1a86_USB_Serial
path   = platform-3f980000.usb-usb-0:1.3:1.0-port0
```

The trade-off: a mapping by port follows the **USB port**, not the adapter.
Keep each cable in its port, or update `devices.conf` after moving it.

## Logging

Set `OOB_LOG_DIR` to log every console to `<dir>/<name>.log`:

```sh
OOB_LOG_DIR="/var/log/oob-usb-serial"
```

When the session is started as root (the boot service, or `sudo`), a missing
directory is created for `OOB_USER`. Otherwise it must exist and be writable
by `OOB_USER`.

tio's logging flags depend on its version; `oob-usb-serial` picks them for
you:

| tio | Release | Flags used | Existing log on restart |
|-----|---------|------------|-------------------------|
| 1.x | Debian 11 | `-l <file>` | handled by tio 1.x |
| 2.0 – 2.5 | Debian 12 | `--log --log-file <file>` | handled by tio 2.x |
| 2.6+, 3.x | Debian 13 | `--log --log-file <file> --log-append` | appended |

Log rotation is up to you (e.g. a `logrotate` rule with `copytruncate`).
