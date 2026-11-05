# Deployment: air-gapped Wi-Fi access box

`oob-usb-serial` runs on any Debian host. For a self-contained out-of-band
console that stays isolated from production and corporate networks, this is
the setup the project is designed around:

- **Raspberry Pi Zero** (Zero W / Zero 2 W) as the console host.
- **Air-gapped**: no uplink to the Internet or any other network. The Pi does
  not route; it only exposes the serial consoles. The OOB path then stays
  independent of whatever it is used to recover.
- **Wi-Fi access point**: the Pi's onboard Wi-Fi broadcasts a dedicated SSID
  (via `hostapd`). Connect to it from a laptop or phone when you need console
  access, with nothing else on that network.
- **Dedicated DHCP range**: `dnsmasq` hands out addresses on an isolated
  subnet (for example `10.10.10.0/24`), so clients that join the SSID can
  reach the Pi over SSH without manual configuration.

Once connected to the SSID, SSH to the Pi as the `oob` user and you land
directly in the console session (see [[Boot and Login|Boot-and-Login]]).

## Hardware notes

- A **powered USB hub** is recommended with several adapters, or when the
  adapters power anything over the serial line. The Pi Zero's single port
  cannot supply much current.
- Prefer adapters with a **unique serial number** (genuine FTDI, CP210x).
  Identical clones without one work, but are then told apart by USB port (see
  [[Configuration#identical-adapters]]).
- Label the cables and keep a `devices.conf` section per console, so window
  names match what is on the other end.

## Scope

This topology is a recommendation, not a dependency: Wi-Fi, an access point
and DHCP are not required. Configure `hostapd` and `dnsmasq` per your
distribution's documentation; they are outside the scope of this package.
