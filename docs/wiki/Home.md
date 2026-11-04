# oob-usb-serial

**Out-of-band USB serial console multiplexer.** Plug a set of USB-to-serial
adapters into a Debian host, cable each one to the console port of a switch,
router or server, and `oob-usb-serial` opens every console at once in one
detached `tmux` session, reachable over SSH.

Each console runs [`tio`](https://tio.github.io) on the adapter's stable
`/dev/serial/*` path, so it reconnects by itself when an adapter is unplugged
and plugged back in.

## Pages

| Page | What's in it |
|------|--------------|
| [[Installation]] | APT repository, single `.deb`, dependencies, supported releases |
| [[Usage]] | Commands, tmux/tio keys, serial permissions, tab completion |
| [[Configuration]] | `oob-usb-serial.conf`, `devices.conf`, identical adapters, logging |
| [[Boot and Login|Boot-and-Login]] | systemd service, `OOB_USER`, login auto-attach |
| [[Deployment]] | Recommended air-gapped Wi-Fi access box |
| [[Troubleshooting]] | Common problems and their fixes |
| [[Design]] | Architecture and the decisions behind it |
| [[Development]] | Building, linting, the test suite, project layout |
| [[Releasing]] | Versioning, release pipeline, APT repository setup |

> These pages are generated from
> [`docs/wiki/`](https://github.com/diaznet/oob-usb-serial/tree/main/docs/wiki)
> in the repository. To change them, open a pull request there; edits made
> directly on the wiki are overwritten.
