#!/usr/bin/env bats
# Discovery: which udev nodes count as serial adapters, and what is reported.

load helpers

setup() { common_setup; }
teardown() { common_teardown; }

discover() { bash "$SRC/lib/discover.sh" "$@"; }

@test "reports a tty adapter with serial, vendor, model, by-id and by-path" {
    add_device ttyUSB0 FTDI_FT232R_A1 FT232R_USB_UART \
        usb-FTDI_FT232R_A1-if00-port0 platform-usb-0:1.2:1.0-port0

    run discover
    [ "$status" -eq 0 ]
    IFS=$'\t' read -r devnode serial vendor model byid bypath <<< "$output"
    [ "$devnode" = "$OOB_DEV_ROOT/ttyUSB0" ]
    [ "$serial" = "FTDI_FT232R_A1" ]
    [ "$vendor" = "FTDI" ]
    [ "$model" = "FT232R_USB_UART" ]
    [ "$byid" = "$OOB_DEV_ROOT/serial/by-id/usb-FTDI_FT232R_A1-if00-port0" ]
    [ "$bypath" = "$OOB_DEV_ROOT/serial/by-path/platform-usb-0:1.2:1.0-port0" ]
}

@test "skips USB disks, HID and other non-tty nodes that carry an ID_SERIAL" {
    add_device ttyUSB0 FTDI_A1
    add_device sda Kingston_DataTraveler Disk - - block block
    add_device hidraw0 Logitech_Keyboard Kbd - - hidraw hidraw
    # A node under a tty/ directory whose udev subsystem is not tty.
    add_device ttyFAKE0 Weird_Device Weird - - misc tty

    run discover
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "${lines[0]}" == "$OOB_DEV_ROOT/ttyUSB0"$'\t'FTDI_A1$'\t'* ]]
}

@test "skips tty nodes without an ID_SERIAL" {
    add_device ttyUSB0 ""
    run discover
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "falls back to the device node when there is no by-id link" {
    add_device ttyUSB0 FTDI_A1
    run discover
    IFS=$'\t' read -r devnode _ _ _ byid bypath <<< "$output"
    [ "$byid" = "$devnode" ]
    [ -z "$bypath" ]
}

@test "output is sorted by device node" {
    add_device ttyUSB2 S2
    add_device ttyACM0 S0
    add_device ttyUSB1 S1
    run discover --nodes
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$OOB_DEV_ROOT/ttyACM0" ]
    [ "${lines[1]}" = "$OOB_DEV_ROOT/ttyUSB1" ]
    [ "${lines[2]}" = "$OOB_DEV_ROOT/ttyUSB2" ]
}

@test "--nodes filters case-insensitively on the whole record" {
    add_device ttyUSB0 FTDI_A1 FT232R
    add_device ttyUSB1 Prolific_B2 PL2303
    run discover --nodes pl2303
    [ "$status" -eq 0 ]
    [ "$output" = "$OOB_DEV_ROOT/ttyUSB1" ]
}

@test "udev property values are never executed" {
    add_device ttyUSB0 FTDI_A1
    # Shell metacharacters in a device-controlled value must stay inert.
    printf "ID_MODEL='\$(touch %s/pwned)'\`touch %s/pwned2\`\n" "$TEST_TMP" "$TEST_TMP" \
        >> "$(props_of ttyUSB0)"

    run discover
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_TMP/pwned" ]
    [ ! -e "$TEST_TMP/pwned2" ]
    [[ "$output" == *'$(touch'* ]]
}

@test "fails cleanly when udevadm is missing" {
    rm "$TEST_TMP/bin/udevadm"
    run env PATH="$TEST_TMP/bin:/usr/bin/env-only-nothing" /bin/bash "$SRC/lib/discover.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"udevadm not found"* ]]
}
