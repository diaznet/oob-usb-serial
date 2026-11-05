# Troubleshooting

## "no adapters discovered; not starting an empty session"

No USB serial adapter was found. Check:

```sh
oob-usb-serial list
ls -l /dev/serial/by-id/ /dev/serial/by-path/
dmesg | grep -i tty
```

Only devices the kernel exposes as a tty (`ttyUSB*`, `ttyACM*`, …) count as
adapters; USB disks, keyboards and the like are ignored. If `dmesg` shows no
tty, the adapter's driver is missing or the cable is power-only.

At boot, the service retries for about five minutes; after that it stays
`failed` until you restart it (see [[Boot and Login|Boot-and-Login]]).

## "cannot access /dev/…: permission denied"

The user running the session cannot open the adapter. The packaged user is in
`dialout`; if you changed `OOB_USER`, run
`sudo dpkg-reconfigure oob-usb-serial`, or add the user yourself:

```sh
sudo usermod -aG dialout <user>
```

## "run this as 'oob'"

Session commands always act on `OOB_USER`'s session. Use
`sudo oob-usb-serial <command>` (it switches to that user), or log in as it.

## A newly plugged adapter has no window

Adapters plugged in after the session started are not added automatically:

```sh
oob-usb-serial restart
```

## Two adapters share one window name, or swap places after a reboot

They report the same `ID_SERIAL` (clones without a serial number, or the ports
of one multi-port adapter). `oob-usb-serial` opens them by USB port; give each
one its own section with a `path` key, or let `sudo oob-usb-serial config`
write them. See [[Configuration#identical-adapters]].

## A console window shows "Pane is dead"

Its tio exited (e.g. invalid settings, or the device vanished while tio was
started with reconnecting disabled). Press `Ctrl-b R` to relaunch it. If it
keeps dying, check the window's last output and `oob-usb-serial list` for
the settings in use.

## "warning: <name>: invalid parity 'mark' …"

A value in `devices.conf` is outside tio's vocabulary for this tool (see
[[Configuration]]). The console still starts, using the global default for
that setting.

## Logging does not produce files

- `OOB_LOG_DIR` must be writable by `OOB_USER`. It is created automatically
  only when the session is started as root.
- tio's logging flags differ between versions; `oob-usb-serial` detects the
  version with `tio --version`. Check what it runs with
  `ps -o args= -C tio`.
