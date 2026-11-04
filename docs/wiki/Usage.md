# Usage

```sh
oob-usb-serial list          # discovered adapters + resolved config
oob-usb-serial start         # start the detached session (one window/adapter)
oob-usb-serial attach        # attach to the session (starts it if needed)
oob-usb-serial status        # is the session running? (exit 0 yes, 3 no)
oob-usb-serial stop          # tear the session down
oob-usb-serial restart       # stop then start (picks up new adapters/config)
sudo oob-usb-serial config   # map adapters into devices.conf
oob-usb-serial discover      # raw tab-separated records, for scripts
```

## Who runs the session

All consoles live in **one** tmux session owned by `OOB_USER` (default `oob`).
The session commands (`start`, `stop`, `restart`, `attach`, `status`) always
act on that user's session:

- as `OOB_USER`: they run directly;
- as root (e.g. `sudo oob-usb-serial attach`): they switch to `OOB_USER`
  first;
- as any other user: they refuse, so nobody accidentally starts a second,
  separate session.

`discover`, `list` and `config` work as any user (`config` needs root to write
under `/etc`).

## Inside the session

| Keys | Action |
|------|--------|
| `Ctrl-b n` / `Ctrl-b p` | next / previous console |
| `Ctrl-b w` | pick a console from a list |
| `Ctrl-b d` | detach (the consoles keep running) |
| `Ctrl-b R` | relaunch a console that has closed |
| `Ctrl-t q` | quit tio in the current console |
| `Ctrl-t ?` | list tio's own key commands |

A console whose tio exits stays visible (with its exit status) instead of
disappearing; `Ctrl-b R` brings it back.

## Mapping adapters: `config`

`sudo oob-usb-serial config` walks each attached adapter that isn't mapped yet
and asks for a window name, baud rate, data bits, parity, stop bits and flow
control. Press Enter to keep the default shown in brackets, or `s` to skip an
adapter. Invalid answers are asked again. Each answer set is appended to
`devices.conf` as one section; apply it with `oob-usb-serial restart`.

If two attached adapters report the same serial (common with cheap clones),
`config` also writes their USB port, so each one gets its own mapping. See
[[Configuration#identical-adapters]].

## `list` output

```
NAME                     FROM  DEVICE        BAUD     FRAMING  ID_SERIAL
----                     ----  ------        ----     -------  ---------
core-sw                  conf  ttyUSB0       9600     8N1      FTDI_FT232R_USB_UART_A5069RR4
    opens: /dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A5069RR4-if00-port0
```

`FROM` is `conf` for adapters matched in `devices.conf` and `auto` for
adapters running on the global defaults. `opens:` is the path tio connects to.

## New adapters

Adapters plugged in **after** the session started are not added
automatically; run `oob-usb-serial restart` to pick them up. Adapters that
were already open reconnect by themselves after a replug.

## Serial device permissions

Serial adapters are owned by the `dialout` group. The packaged session user
is added to it at install. To open the adapters as your own login (e.g. for
`tio` by hand), add yourself and log in again:

```sh
sudo usermod -aG dialout "$USER"
```

## Tab completion

With `bash-completion` installed, `oob-usb-serial <Tab>` completes the
subcommands in new shells. To enable it in the current shell:

```sh
source /usr/share/bash-completion/completions/oob-usb-serial
```
