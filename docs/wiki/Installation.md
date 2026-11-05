# Installation

The tool ships as one Debian package. It is pure shell, so the package is
architecture-independent (`Architecture: all`) and installs on armhf (Pi
Zero), arm64 and amd64 alike.

## Supported releases

Debian 11 (bullseye), 12 (bookworm) and 13 (trixie), and the Raspberry Pi OS
and Ubuntu releases based on them. The test suite runs on all three Debian
releases in CI.

The tio command-line changed between versions (1.x on Debian 11, 2.x on
Debian 12, 3.x on Debian 13); `oob-usb-serial` detects the installed version
and passes the right flags.

## Recommended: the signed APT repository

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

## Alternative: download a single `.deb`

Grab a `.deb` from the
[Releases page](https://github.com/diaznet/oob-usb-serial/releases). Install
it with `apt install ./file.deb` (not `dpkg -i`) so the runtime dependencies
resolve automatically:

```sh
ver=2.1.0
wget "https://github.com/diaznet/oob-usb-serial/releases/download/v${ver}/oob-usb-serial_${ver}_all.deb"
sudo apt install "./oob-usb-serial_${ver}_all.deb"
```

## What the package does at install

- Creates the session user (`OOB_USER` from
  `/etc/oob-usb-serial/oob-usb-serial.conf`, default `oob`) as a system user
  and adds it to `dialout` so it can open the serial adapters.
- Installs and enables `oob-usb-serial.service` (see [[Boot and Login|Boot-and-Login]]).
- Installs the two config files as dpkg *conffiles*: your edits survive
  upgrades (see [[Design#packaging-and-upgrades]]).

## Dependencies

Nothing is bundled or vendored:

| Kind | Packages | Managed by |
|------|----------|------------|
| Runtime (required) | `tio`, `tmux`, `udev`, `adduser` | `Depends:` in the package; `apt` installs them |
| Runtime (optional) | `bash-completion` | `Recommends:` |
| Build-time only | `dpkg-dev`, `debhelper`, `fakeroot` | your build host / CI |

There is no language runtime (no Python/Node): the tool is `bash` plus `tio`
and `tmux`.

## Removing

```sh
sudo apt remove oob-usb-serial     # keeps /etc/oob-usb-serial
sudo apt purge oob-usb-serial      # also removes the config files
```

The session user is left in place either way; remove it with
`sudo deluser oob` if you no longer need it.
