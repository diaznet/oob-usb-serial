# Development

## Project layout

```
src/bin/oob-usb-serial          main CLI
src/lib/discover.sh             udev-based adapter discovery
src/lib/session-gen.sh          config lookup, tio command, tmux config
src/etc/*.conf                  default + example configuration
src/systemd/*.service           boot-time service unit
src/profile/oob-usb-serial.sh   opt-in login auto-attach snippet
src/completion/oob-usb-serial   bash completion
src/man/oob-usb-serial.1        man page
tests/                          bats test suite
debian/                         Debian packaging
docs/wiki/                      these wiki pages (published by CI)
docs/apt/                       APT repository landing page + public key
scripts/                        APT signing key setup, APT repo builder
Makefile                        install (DESTDIR/PREFIX), check, test
build.sh / build.ps1            cross-platform package build
.github/workflows/              CI, release, APT repository, wiki
```

## Lint and test

```sh
make check     # shellcheck on every shell file
make test      # bats suite
```

`make test` needs `bats` and `tmux` (`sudo apt install bats tmux`). Pass
`BATS=/path/to/bats` to use another bats, e.g. a
[bats-core](https://github.com/bats-core/bats-core) checkout. Run it as a
normal user: a few permission tests are skipped as root.

On Windows, run both in WSL (a Debian/Ubuntu distro). Copy the tree to the
Linux file system first; permission tests misbehave on `/mnt/c`.

### How the tests work

The suite never touches real devices, `/etc` or your tmux sessions.
`tests/helpers.bash` builds a private scratch tree per test and points the
code at it through environment hooks:

| Variable | Default | Test use |
|----------|---------|----------|
| `OOB_SYSFS_ROOT` | `/sys` | fake sysfs tree with USB tty (and non-tty) nodes |
| `OOB_DEV_ROOT` | `/dev` | fake device nodes and `serial/by-id`, `serial/by-path` links |
| `OOB_CONF`, `OOB_DEVICES_CONF` | `/etc/oob-usb-serial/…` | scratch config files |
| `OOB_RUNTIME_DIR` | `/run/oob-usb-serial` | scratch runtime dir |
| `OOB_TMUX_SOCKET` | `oob` | private tmux socket per test |
| `OOB_LIB_DIR` | auto | library location (source tree is found automatically) |

Fake `udevadm` and `tio` scripts come first on `PATH`: `udevadm` serves the
fixture's properties, and `tio` reports `$FAKE_TIO_VERSION`, logs its
arguments and idles like a connected console. tmux is real.

| File | Covers |
|------|--------|
| `tests/discover.bats` | device filtering, record fields, sorting, no `eval` of udev values |
| `tests/session-gen.bats` | config lookup, validation, naming, target choice, tio flags per version, runtime dir |
| `tests/config.bats` | the `config` prompts and what they write |
| `tests/session.bats` | start/stop/restart/status/list against real tmux, user checks |

CI runs the suite in Debian 11, 12 and 13 containers (as an unprivileged
user) and on Ubuntu, then builds the package, runs lintian, installs it and
checks the service unit with `systemd-analyze verify`.

## Build the package

A `.deb` can only be produced by Debian tooling; the build scripts make that
work from Windows, macOS or Linux.

- **Linux / WSL**: native build with `dpkg-buildpackage`

  ```sh
  ./build.sh              # version from git tag, or debian/changelog
  ./build.sh 1.2.0        # explicit version
  ```

  Requires `dpkg-dev debhelper fakeroot`.

- **Windows**: via WSL or Docker (auto-detected)

  ```powershell
  .\build.ps1
  .\build.ps1 -Version 1.2.0
  .\build.ps1 -Distro Ubuntu     # if your default WSL distro lacks dpkg-dev
  .\build.ps1 -Backend docker
  ```

- **macOS**: via Docker

  ```sh
  OOB_FORCE_DOCKER=1 ./build.sh
  ```

The package is written to `dist/oob-usb-serial_<version>_all.deb`. Built
packages are not committed; they are published through GitHub Releases (see
[[Releasing]]).

## Documentation

User documentation is this wiki, kept in `docs/wiki/`. Update the matching
page in the same pull request as a behaviour change. GitHub wiki links use
`[[Page]]` / `[[Text|Page]]`. The `Wiki` workflow publishes the folder when
it changes on `main`.
