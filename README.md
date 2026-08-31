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
  <img alt="Package: deb (Architecture: all)" src="https://img.shields.io/badge/package-deb%20(all)-blue">
  <img alt="Shell: bash" src="https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white">
</p>

---

Plug a set of USB-to-serial adapters into a Debian host through a USB hub, cable
each adapter to the console port of a switch, router or server, and
`oob-usb-serial` exposes every console at once from one detached GNU `screen`
session — reachable over SSH.

## How it works

1. **Discover** every attached USB-to-serial adapter via `udev`, keyed by the
   adapter's *stable* serial identifier (`ID_SERIAL`) rather than its
   `/dev/ttyUSBx` node, which can change across reboots and replugs.
2. **Resolve** each adapter against an optional per-device config (friendly
   name, baud rate, serial framing). Unmapped adapters use global defaults.
3. **Open** all adapters as named windows inside one detached GNU `screen`
   session, so `screen -r oob` (or an SSH login) drops you into all consoles.

## Hardware

Any hardware running Debian (or a Debian derivative
such as Raspberry Pi OS or Ubuntu) works:

- A Debian host: a Raspberry Pi (Zero, 3, 4, ...) makes a tidy, low-power OOB
  box, but a mini PC, VM or laptop is equally fine.
- One or more USB-to-serial adapters (FTDI, Prolific, CP210x, ...).
- Optional: A USB hub (powered or unpowered). A powered hub is recommended when running
  several adapters or driving devices that draw power over the serial line.

## Recommended deployment: air-gapped Wi-Fi access box

For a self-contained out-of-band console that stays isolated from your
production and corporate networks, the setup below works well and is the one
this project is designed around:

- **Raspberry Pi Zero** (Zero W / Zero 2 W) as the console host.
- **Air-gapped** — no uplink to the Internet or any other network. The Pi does
  not route; it only exposes the serial consoles. This keeps the OOB path
  independent of whatever it is used to recover.
- **Wi-Fi access point** — the Pi's onboard Wi-Fi broadcasts a dedicated SSID
  (via `hostapd`). You connect straight to it from a laptop or phone when you
  need console access, with nothing else on that network.
- **Dedicated DHCP range** — `dnsmasq` hands out addresses on an isolated
  subnet (for example `10.10.10.0/24`) so clients that join the SSID get an IP
  and can reach the Pi over SSH without any manual configuration.

Once connected to the SSID, SSH to the Pi as the `oob` user and you land
directly in the console session (see *Boot and login integration* below).

> This topology is a recommendation, not a dependency: `oob-usb-serial` runs on
> any Debian host and does not require Wi-Fi, an access point, or DHCP. Set up
> `hostapd`/`dnsmasq` per your distro's documentation; their configuration is
> outside the scope of this package.

## Install

The tool is distributed as a single Debian package. Because it is pure shell,
the package is architecture-independent (`Architecture: all`, the Debian
equivalent of "noarch") and installs on armhf (Pi Zero), arm64 and amd64 alike.

### Recommended: the signed APT repository

Add the repository once, then install and upgrade by name like any other
package. The archive is GPG-signed and served over HTTPS from GitHub Pages.

```sh
# 1. Trust the repository signing key
curl -fsSL https://diaznet.github.io/oob-usb-serial/pubkey.gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/oob-usb-serial.gpg

# 2. Add the repository
echo "deb [signed-by=/usr/share/keyrings/oob-usb-serial.gpg] \
https://diaznet.github.io/oob-usb-serial stable main" \
  | sudo tee /etc/apt/sources.list.d/oob-usb-serial.list

# 3. Install
sudo apt update
sudo apt install oob-usb-serial
```

Upgrade later with:

```sh
sudo apt update && sudo apt install --only-upgrade oob-usb-serial
```

### Alternative: download a single `.deb`

If you'd rather not add the repository, grab a `.deb` from the
[Releases page](https://github.com/diaznet/oob-usb-serial/releases) and
install it. Use `apt install ./file.deb` (not `dpkg -i`) so the runtime
dependencies resolve automatically:

```sh
ver=1.0.0
wget "https://github.com/diaznet/oob-usb-serial/releases/download/v${ver}/oob-usb-serial_${ver}_all.deb"
sudo apt install "./oob-usb-serial_${ver}_all.deb"
```

### Dependencies

Dependency handling is declarative — nothing is bundled or vendored:

| Kind | Packages | Managed by |
|------|----------|------------|
| Runtime (required) | `screen`, `udev`, `adduser` | `Depends:` in the package; `apt` installs them |
| Runtime (optional) | `dialog` (only for interactive mode) | `Recommends:` in the package |
| Build-time only | `dpkg-dev`, `debhelper`, `fakeroot` | installed by CI / your build host |

There is no language runtime dependency (no Python/Node): the tool is `bash`
plus standard coreutils and `stty`, which are always present.

## Usage

```sh
oob-usb-serial list          # show discovered adapters + resolved config
oob-usb-serial start         # start the detached session (one window/adapter)
oob-usb-serial attach        # attach to the session (starts it if needed)
oob-usb-serial status        # is the session running?
oob-usb-serial stop          # tear the session down
oob-usb-serial interactive   # dialog picker: speed, framing, then device
sudo oob-usb-serial config   # interactively map adapters into devices.conf
```

`config` walks each attached adapter that isn't already mapped and prompts for a
window name, baud rate and framing, then appends the matching INI section to
`devices.conf` for you (matched by the adapter's exact `ID_SERIAL`). It needs
root to write under `/etc`. Use `oob-usb-serial config --generate` to just print
the generated screenrc without changing anything.

Inside the shared `screen` session (`start`/`attach`): `Ctrl-a n` / `Ctrl-a p`
switch consoles, `Ctrl-a "` lists them, `Ctrl-a d` detaches.

`interactive` prompts for a baud rate, a **framing**, and the device, then opens
it in a plain `screen` session; leave it with `Ctrl-a k` (kill the window) or
`Ctrl-a \` (quit screen). For framing you can either pick a **preset**, or
choose **Custom** to set data bits, parity, stop bits and flow control
individually. The presets are read from
`/usr/share/oob-usb-serial/serial_framings.txt` (`label|stty-options` per
line) — edit that file to add or change presets.

### Serial device permissions

Serial adapters (`/dev/ttyUSB*`) are owned by the `dialout` group. A user must
be in that group to open them — otherwise `screen` opens the port and exits
immediately (`[screen is terminating]`). The commands detect this and print a
hint.

- The packaged **`oob`** user is added to `dialout` automatically at install
  time, so the boot service and login integration work out of the box.
- To use the tool as your **own** login (e.g. `pi`), add yourself once and log
  back in:

  ```sh
  sudo usermod -aG dialout "$USER"
  # then log out and back in (group changes apply to new sessions)
  ```

Running under `sudo` also works but is discouraged for an interactive session.

### Tab completion

The package ships a bash completion script to
`/usr/share/bash-completion/completions/oob-usb-serial`. With the
`bash-completion` package installed, `oob-usb-serial <Tab>` completes the
subcommands (and `--generate` after `config`). It activates in new shells; to
enable it in the current shell without re-login:

```sh
source /usr/share/bash-completion/completions/oob-usb-serial
```

## Configuration

### Global defaults — `/etc/oob-usb-serial/oob-usb-serial.conf`

```sh
OOB_DEFAULT_SPEED="9600"
OOB_DEFAULT_FRAMING="cs8,-parenb,-cstopb"   # 8N1
OOB_SESSION_NAME="oob"
OOB_USER="oob"
```

### Per-device mapping — `/etc/oob-usb-serial/devices.conf`

An INI file. Each `[section]` defines one device, and **the section name is the
`screen` window title**. Match adapters by their `ID_SERIAL` (see
`oob-usb-serial list`). The file may be left empty — every adapter then opens at
the global defaults.

```ini
[device1]
match   = *FT232R*_A5069RR4
baud    = 9600
framing = cs8,-parenb,-cstopb

[device2]
match   = *Prolific*
baud    = 38400
framing = cs8,parenb,cstopb,crtscts

[device3]
match   = *CP2102*
baud    = 115200
; framing omitted -> uses OOB_DEFAULT_FRAMING
```

| Key | Meaning | Required |
|-----|---------|----------|
| `match` | shell glob matched against the adapter's udev `ID_SERIAL` | yes |
| `baud` | baud rate (e.g. `9600`, `115200`) | no — falls back to `OOB_DEFAULT_SPEED` |
| `framing` | comma-separated `stty` options | no — falls back to `OOB_DEFAULT_FRAMING` |

Sections are matched in file order; the first section whose `match` glob fits an
adapter wins. Comments start with `#` or `;`.

Framing is a comma-separated list of `stty` options: `cs7`/`cs8` data bits,
`parenb`/`-parenb` parity, `cstopb`/`-cstopb` stop bits, `crtscts` for hardware
flow control.

Both config files are registered as dpkg *conffiles*, so your edits survive
package upgrades.

## Boot and login integration

Enable the session at boot:

```sh
sudo systemctl enable --now oob-usb-serial.service
```

The service runs as the `oob` user created at install time. To run as a
different user, edit `User=` in `/lib/systemd/system/oob-usb-serial.service`
(or add a systemd drop-in) and update `OOB_USER` in the config.

To drop straight into the consoles on SSH login as the `oob` user, enable the
opt-in login snippet:

```sh
sudo -u oob ln -s /usr/share/oob-usb-serial/profile/oob-usb-serial.sh \
    ~oob/.oob-login.sh
echo '. ~/.oob-login.sh' | sudo -u oob tee -a ~oob/.bash_profile
```

## Versioning and releases

The project uses [Semantic Versioning](https://semver.org/):
`vMAJOR.MINOR.PATCH`.

Releases are cut by pushing a git tag. The version flows from the tag into the
built package automatically — you do not hand-edit the package version:

```sh
git tag v1.2.0
git push origin v1.2.0
```

Pushing a `v*.*.*` tag triggers the **Release** GitHub Actions workflow
(`.github/workflows/release.yml`), which:

1. derives the version from the tag (`v1.2.0` -> `1.2.0`),
2. runs ShellCheck,
3. builds the `.deb` with that version,
4. publishes it as an asset on a new GitHub Release (with auto-generated notes).

Once the release is published, the **APT repository** workflow
(`.github/workflows/apt-repo.yml`) rebuilds the signed archive from *all*
published releases and deploys it to GitHub Pages, so `apt install
oob-usb-serial` immediately serves the new version.

Every push and pull request to `main` also runs the **CI** workflow
(`.github/workflows/ci.yml`): ShellCheck, a test build, `lintian`, and the
`.deb` uploaded as a build artifact.

### Maintainer: one-time repository setup

The APT archive is GPG-signed, which requires a signing key that you own. This
is a one-time setup:

1. Generate the key and export it (helper script):

   ```sh
   ./scripts/setup-apt-signing-key.sh
   ```

   This writes the **public** key to `docs/apt/pubkey.gpg` (commit it) and the
   **private** key to a local file (never commit it).

2. Add the private key as the `APT_GPG_PRIVATE_KEY` GitHub Actions secret (the
   script prints the exact `gh secret set` command), then delete the local
   private key file.

3. Enable GitHub Pages: **Settings → Pages → Source: GitHub Actions**.

After that, every release automatically publishes to the signed APT repo.

## Building locally

A `.deb` can only be produced by Debian tooling. The build scripts make that
work from Windows, macOS or Linux:

- **Linux / WSL** — native build (uses `dpkg-buildpackage`):

  ```sh
  ./build.sh              # version from git tag, or debian/changelog
  ./build.sh 1.2.0        # explicit version
  ```

  Requires `dpkg-dev debhelper fakeroot` (and `shellcheck` for `make check`).

- **Windows** — via WSL or Docker (auto-detected):

  ```powershell
  .\build.ps1
  .\build.ps1 -Version 1.2.0
  .\build.ps1 -Distro Ubuntu     # if your default WSL distro lacks dpkg-dev
  .\build.ps1 -Backend docker
  ```

  The WSL backend needs a Debian/Ubuntu distro with `dpkg-dev debhelper
  fakeroot` installed. If your default WSL distro is different, pass `-Distro`.

- **macOS** — via Docker:

  ```sh
  OOB_FORCE_DOCKER=1 ./build.sh
  ```

The finished package is written to `dist/oob-usb-serial_<version>_all.deb`.
Built packages are not committed to the repository; they are published through
GitHub Releases.

Lint the shell sources at any time:

```sh
make check     # runs shellcheck
```

## Project layout

```
src/bin/oob-usb-serial          # main CLI
src/lib/discover.sh             # udev-based adapter discovery
src/lib/screenrc-gen.sh         # config -> screenrc generator
src/etc/*.conf                  # default + example configuration
src/systemd/*.service           # boot-time service unit
src/profile/oob-usb-serial.sh   # opt-in login auto-attach snippet
src/man/oob-usb-serial.1        # man page
debian/                         # Debian packaging
Makefile                        # install rules (honours DESTDIR/PREFIX)
build.sh / build.ps1            # cross-platform package build
scripts/setup-apt-signing-key.sh  # one-time GPG signing key setup
scripts/build-apt-repo.sh       # assemble + sign the APT archive
docs/apt/                       # APT repo landing page + public key
.github/workflows/              # CI + release + APT repo pipelines
```

## License

MIT. See [LICENSE](LICENSE).
