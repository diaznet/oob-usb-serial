<h1 align="center">🔌 oob-usb-serial</h1>

<p align="center">
  <strong>Out-of-band USB serial console multiplexer</strong><br>
  Turn any Debian box into a single SSH-reachable jump host for all your serial consoles.
</p>

<p align="center">
  <a href="https://github.com/diaznet/oob-usb-serial/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/diaznet/oob-usb-serial/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/diaznet/oob-usb-serial/actions/workflows/release.yml"><img alt="Release" src="https://github.com/diaznet/oob-usb-serial/actions/workflows/release.yml/badge.svg"></a>
  <a href="https://github.com/diaznet/oob-usb-serial/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/diaznet/oob-usb-serial?sort=semver"></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-yellow.svg"></a>
</p>

<p align="center">
  📖 <strong><a href="https://github.com/diaznet/oob-usb-serial/wiki">Documentation: the project wiki</a></strong>
</p>

---

Plug a set of USB-to-serial adapters into a Debian host, cable each one to the
console port of a switch, router or server, and `oob-usb-serial` opens every
console at once in one detached `tmux` session, reachable over SSH.

## How it works

1. **Discover** every USB serial adapter through `udev`, identified by its
   stable serial number (`ID_SERIAL`) rather than its `/dev/ttyUSBx` node,
   which changes across reboots and replugs.
2. **Resolve** each adapter against an optional per-device config (console
   name, baud rate, framing); unmapped adapters use global defaults.
3. **Open** them all as named windows of one `tmux` session, each running
   [`tio`](https://tio.github.io) on a stable `/dev/serial/*` path, so a
   console reconnects by itself after a replug.

Details: [Design](https://github.com/diaznet/oob-usb-serial/wiki/Design).

## Hardware

- A Debian host (Debian 11+, Raspberry Pi OS, Ubuntu). A Raspberry Pi Zero
  makes a tidy, low-power box; a mini PC, VM or laptop works too.
- One or more USB-to-serial adapters (FTDI, CP210x, Prolific, CH340, …).
- Optional: a USB hub. Use a powered one with several adapters.

Recommended setup: [an air-gapped Wi-Fi access box](https://github.com/diaznet/oob-usb-serial/wiki/Deployment).

## Install

From the signed APT repository:

```sh
curl -fsSL https://diaznet.github.io/oob-usb-serial/pubkey.gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/oob-usb-serial.gpg
echo "deb [signed-by=/usr/share/keyrings/oob-usb-serial.gpg] \
https://diaznet.github.io/oob-usb-serial stable main" \
  | sudo tee /etc/apt/sources.list.d/oob-usb-serial.list
sudo apt update && sudo apt install oob-usb-serial
```

Single `.deb`, dependencies and supported releases:
[Installation](https://github.com/diaznet/oob-usb-serial/wiki/Installation).

## Usage

```sh
oob-usb-serial list          # discovered adapters + resolved config
sudo oob-usb-serial config   # name adapters and set their serial settings
oob-usb-serial attach        # open the consoles (starts the session if needed)
oob-usb-serial restart       # pick up new adapters or config changes
```

In the session: `Ctrl-b n` / `Ctrl-b p` switch consoles, `Ctrl-b w` lists
them, `Ctrl-b d` detaches, `Ctrl-b R` relaunches a closed console.

More: [Usage](https://github.com/diaznet/oob-usb-serial/wiki/Usage) ·
[Configuration](https://github.com/diaznet/oob-usb-serial/wiki/Configuration) ·
[Boot and login](https://github.com/diaznet/oob-usb-serial/wiki/Boot-and-Login) ·
[Troubleshooting](https://github.com/diaznet/oob-usb-serial/wiki/Troubleshooting) ·
`man oob-usb-serial`

## License

MIT. See [LICENSE](LICENSE).
