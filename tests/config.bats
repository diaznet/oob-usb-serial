#!/usr/bin/env bats
# `oob-usb-serial config`: the interactive devices.conf scaffolder.

load helpers

setup() { common_setup; }
teardown() { common_teardown; }

# answer <line>... — feed one answer per prompt to `config`.
config_with() { printf '%s\n' "$@" | "$CLI" config; }

lookup() { lib _oob_lookup_config "$@"; }

@test "writes a section that reads back through the lookup" {
    add_device ttyUSB0 FTDI_A1
    run config_with "core-sw" 9600 7 even 2 hard
    [ "$status" -eq 0 ]
    [[ "$output" == *"added [core-sw] (match = FTDI_A1)"* ]]
    run lookup FTDI_A1
    [ "$output" = "core-sw|9600|7|even|2|hard" ]
}

@test "Enter accepts every default" {
    add_device ttyUSB0 FTDI_A1 FT232R
    run config_with "" "" "" "" "" ""
    [ "$status" -eq 0 ]
    run lookup FTDI_A1
    [ "$output" = "FT232R_FTDI_A1|115200|8|none|1|none" ]
}

@test "invalid answers are asked again" {
    add_device ttyUSB0 FTDI_A1
    run config_with sw fast 9600 9 8 mark odd 3 1 rts hard
    [ "$status" -eq 0 ]
    [ "$(grep -c 'invalid value' <<< "$output")" -eq 5 ]
    run lookup FTDI_A1
    [ "$output" = "sw|9600|8|odd|1|hard" ]
}

@test "names are sanitized before they are written" {
    add_device ttyUSB0 FTDI_A1
    run config_with "core switch]" "" "" "" "" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *'using "core_switch"'* ]]
    grep -qx '\[core_switch\]' "$OOB_DEVICES_CONF"
}

@test "'s' skips a device; already mapped devices are skipped" {
    add_device ttyUSB0 FTDI_A1
    add_device ttyUSB1 FTDI_B2
    printf '[known]\nmatch = FTDI_A1\n' > "$OOB_DEVICES_CONF"
    run config_with s
    [ "$status" -eq 0 ]
    [[ "$output" == *'already mapped as "known"'* ]]
    [[ "$output" == *"skipped."* ]]
    [[ "$output" == *"No new mappings added."* ]]
}

@test "adapters sharing an ID_SERIAL get a path key each" {
    add_device ttyUSB0 1a86_USB_Serial USB_Serial - platform-usb-0:1.2:1.0-port0
    add_device ttyUSB1 1a86_USB_Serial USB_Serial - platform-usb-0:1.3:1.0-port0
    run config_with rack-a "" "" "" "" "" rack-b "" "" "" "" ""
    [ "$status" -eq 0 ]
    grep -qx 'path   = platform-usb-0:1.2:1.0-port0' "$OOB_DEVICES_CONF"
    grep -qx 'path   = platform-usb-0:1.3:1.0-port0' "$OOB_DEVICES_CONF"
    run lookup 1a86_USB_Serial "$OOB_DEV_ROOT/serial/by-path/platform-usb-0:1.3:1.0-port0"
    [ "${output%%|*}" = "rack-b" ]
}

@test "refuses a devices.conf it cannot write" {
    [ "$(id -u)" -ne 0 ] || skip "root can write anything"
    add_device ttyUSB0 FTDI_A1
    chmod 0444 "$OOB_DEVICES_CONF"
    run config_with sw
    [ "$status" -ne 0 ]
    [[ "$output" == *"re-run with sudo"* ]]
}

@test "no adapters: nothing to do" {
    run "$CLI" config
    [ "$status" -eq 0 ]
    [[ "$output" == *"No USB serial adapters found"* ]]
}
