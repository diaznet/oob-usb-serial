# Boot and login

## Start the consoles at boot

```sh
sudo systemctl enable --now oob-usb-serial.service
```

The package enables the service at install; this command is only needed if
you disabled it.

### How the service runs

The unit starts `oob-usb-serial start` as root. The script reads `OOB_USER`
from `/etc/oob-usb-serial/oob-usb-serial.conf`, creates `/run/oob-usb-serial`
(and `OOB_LOG_DIR`, if set and missing) for that user, then switches to it
with `runuser`. The tmux session therefore always belongs to `OOB_USER`: to
run it as someone else, change `OOB_USER` (see
[[Configuration#changing-oob_user]]) — don't add `User=` to the unit.

### No adapters at boot

If no adapter is found yet when the service starts (USB still enumerating, or
nothing plugged in), the start fails and systemd retries every 15 seconds. It
gives up after 10 attempts in 5 minutes and the unit shows `failed`; plug the
adapters in and run:

```sh
sudo systemctl restart oob-usb-serial
```

### Useful commands

```sh
systemctl status oob-usb-serial
journalctl -u oob-usb-serial -b
sudo oob-usb-serial status          # the session itself
```

## Land in the consoles on SSH login

To drop straight into the consoles when logging in as the session user,
enable the opt-in login snippet:

```sh
sudo -u oob ln -s /usr/share/oob-usb-serial/profile/oob-usb-serial.sh \
    ~oob/.oob-login.sh
echo '. ~/.oob-login.sh' | sudo -u oob tee -a ~oob/.bash_profile
```

The packaged user is a system account without a password; give it SSH access
the way you prefer (an `authorized_keys` file, or `sudo passwd oob`).

The snippet only acts in interactive shells and never inside tmux. It runs
`oob-usb-serial attach` (starting the session if needed). Detaching
(`Ctrl-b d`) returns to the shell; add `exit` after the line in
`.bash_profile` if detaching should log out instead.
