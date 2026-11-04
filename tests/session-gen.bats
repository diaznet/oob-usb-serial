#!/usr/bin/env bats
# Session generator: config lookup, validation, naming, targets, tio flags.

load helpers

setup() { common_setup; }
teardown() { common_teardown; }

conf() { printf '%s\n' "$@" > "$OOB_DEVICES_CONF"; }

# --- _oob_lookup_config ----------------------------------------------------

@test "lookup: first matching section wins, omitted keys use defaults" {
    conf '[first]' 'match = *FT232R*' 'baud = 9600' \
         '[second]' 'match = *' 'baud = 19200'
    run lib _oob_lookup_config FTDI_FT232R_A1
    [ "$output" = "first|9600|8|none|1|none" ]
    run lib _oob_lookup_config Other_Serial
    [ "$output" = "second|19200|8|none|1|none" ]
}

@test "lookup: comments, blank lines and unknown/legacy keys are ignored" {
    conf '# comment' '' '; other comment' '[sw1]   # trailing' \
         'match  = A1   ; trailing' 'framing = cs8,-parenb' 'parity = even'
    run lib _oob_lookup_config A1
    [ "$output" = "sw1|115200|8|even|1|none" ]
}

@test "lookup: no file or no match prints nothing" {
    rm -f "$OOB_DEVICES_CONF"
    run lib _oob_lookup_config A1
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    conf '[x]' 'match = B*'
    run lib _oob_lookup_config A1
    [ -z "$output" ]
}

@test "lookup: path key matches the by-path link (basename or full path)" {
    conf '[rack-a]' 'match = 1a86_USB_Serial' 'path = *usb-0:1.2:1.0-port0' \
         '[rack-b]' 'match = 1a86_USB_Serial' 'path = /dev/serial/by-path/*1.3:1.0*'
    run lib _oob_lookup_config 1a86_USB_Serial /dev/serial/by-path/platform-usb-0:1.2:1.0-port0
    [ "${output%%|*}" = "rack-a" ]
    run lib _oob_lookup_config 1a86_USB_Serial /dev/serial/by-path/platform-usb-0:1.3:1.0-port0
    [ "${output%%|*}" = "rack-b" ]
    # A path-only section never matches an adapter without a by-path link.
    run lib _oob_lookup_config 1a86_USB_Serial ""
    [ -z "$output" ]
}

@test "lookup: a path-only section is allowed; a section with neither key is not" {
    conf '[empty]' 'baud = 9600' '[port]' 'path = *1.4:1.0*'
    run lib _oob_lookup_config Any_Serial /x/platform-usb-0:1.4:1.0-port0
    [ "${output%%|*}" = "port" ]
}

# --- helpers ----------------------------------------------------------------

@test "sanitize_name keeps [A-Za-z0-9_.-] and collapses the rest" {
    run lib _oob_sanitize_name 'core switch/1:a]'
    [ "$output" = "core_switch_1_a" ]
}

@test "framing summary" {
    run lib _oob_framing_summary 8 none 1 none;  [ "$output" = "8N1" ]
    run lib _oob_framing_summary 7 even 2 hard;  [ "$output" = "7E2/hard" ]
    run lib _oob_framing_summary 8 odd 1 soft;   [ "$output" = "8O1/soft" ]
}

@test "validators accept tio vocabulary and reject the rest" {
    for v in 9600 115200; do lib _oob_valid_baud "$v"; done
    for v in 0 -1 fast 96k ""; do refute lib _oob_valid_baud "$v"; done
    for v in 5 6 7 8; do lib _oob_valid_data "$v"; done
    for v in 4 9 x; do refute lib _oob_valid_data "$v"; done
    for v in none odd even; do lib _oob_valid_parity "$v"; done
    for v in mark space N; do refute lib _oob_valid_parity "$v"; done
    for v in 1 2; do lib _oob_valid_stop "$v"; done
    refute lib _oob_valid_stop 1.5
    for v in none soft hard; do lib _oob_valid_flow "$v"; done
    refute lib _oob_valid_flow rtscts
}

@test "pick_target prefers by-id, uses by-path for shared serials" {
    run lib _oob_pick_target /d/by-id/x /d/by-path/p /dev/ttyUSB0 0;  [ "$output" = "/d/by-id/x" ]
    run lib _oob_pick_target /d/by-id/x /d/by-path/p /dev/ttyUSB0 1;  [ "$output" = "/d/by-path/p" ]
    run lib _oob_pick_target /dev/ttyUSB0 /d/by-path/p /dev/ttyUSB0 0; [ "$output" = "/d/by-path/p" ]
    run lib _oob_pick_target /dev/ttyUSB0 "" /dev/ttyUSB0 1;            [ "$output" = "/dev/ttyUSB0" ]
}

# --- oob_resolve ------------------------------------------------------------

@test "resolve: unmapped adapters get an auto name and the defaults" {
    add_device ttyUSB0 FTDI_A1 FT232R_USB_UART usb-FTDI_A1-if00-port0
    run lib oob_resolve
    [ "$status" -eq 0 ]
    IFS=$'\t' read -r name baud data parity stop flow target devnode serial mapped bypath <<< "$output"
    [ "$name" = "FT232R_USB_UART_FTDI_A1" ]
    [ "$baud/$data/$parity/$stop/$flow" = "115200/8/none/1/none" ]
    [ "$target" = "$OOB_DEV_ROOT/serial/by-id/usb-FTDI_A1-if00-port0" ]
    [ "$mapped" = "no" ]
}

@test "resolve: invalid configured values fall back to defaults with a warning" {
    add_device ttyUSB0 A1
    conf '[sw]' 'match = A1' 'baud = fast' 'parity = mark' 'data = 7'
    run lib oob_resolve
    [ "$status" -eq 0 ]
    [[ "$output" == *"invalid baud 'fast'"* ]]
    [[ "$output" == *"invalid parity 'mark'"* ]]
    [[ "$output" == *$'sw\t115200\t7\tnone\t1\tnone\t'* ]]
}

@test "resolve: configured names are sanitized and duplicates made unique" {
    add_device ttyUSB0 A1
    add_device ttyUSB1 A2
    add_device ttyUSB2 A3
    conf '[core switch]' 'match = A*'
    run lib oob_resolve
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "core_switch core_switch-2 core_switch-3 " ]
}

@test "resolve: adapters sharing an ID_SERIAL open by USB port with distinct names" {
    add_device ttyUSB0 1a86_USB_Serial USB_Serial usb-1a86_USB_Serial-if00-port0 platform-usb-0:1.2:1.0-port0
    add_device ttyUSB1 1a86_USB_Serial USB_Serial -                              platform-usb-0:1.3:1.0-port0
    run lib oob_resolve
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "${lines[0]}" | cut -f7)" = "$OOB_DEV_ROOT/serial/by-path/platform-usb-0:1.2:1.0-port0" ]
    [ "$(printf '%s\n' "${lines[1]}" | cut -f7)" = "$OOB_DEV_ROOT/serial/by-path/platform-usb-0:1.3:1.0-port0" ]
    [ "$(printf '%s\n' "${lines[0]}" | cut -f1)" = "USB_Serial_1a86_USB_Seri_1.2_1.0" ]
    [ "$(printf '%s\n' "${lines[1]}" | cut -f1)" = "USB_Serial_1a86_USB_Seri_1.3_1.0" ]
}

# --- tio command ------------------------------------------------------------

@test "tio command: serial settings and target, no logging by default" {
    run lib _oob_tio_command sw1 /dev/serial/by-id/x 9600 7 even 2 hard
    [ "$output" = "tio -b 9600 -d 7 -p even -s 2 -f hard /dev/serial/by-id/x" ]
}

@test "tio command: target paths are shell-quoted" {
    run lib _oob_tio_command sw1 '/dev/serial/by-id/a b$(x)' 9600 8 none 1 none
    [[ "$output" == *'/dev/serial/by-id/a\ b\$\(x\)' ]]
}

@test "tio logging: 1.x uses -l <file>" {
    export FAKE_TIO_VERSION="tio v1.32" OOB_LOG_DIR=/var/log/oob/
    run lib _oob_tio_command sw1 /dev/x 115200 8 none 1 none
    [ "$output" = "tio -b 115200 -d 8 -p none -s 1 -f none -l /var/log/oob/sw1.log /dev/x" ]
}

@test "tio logging: 2.0-2.5 use --log --log-file" {
    export FAKE_TIO_VERSION="tio v2.5" OOB_LOG_DIR=/var/log/oob
    run lib _oob_tio_command sw1 /dev/x 115200 8 none 1 none
    [ "$output" = "tio -b 115200 -d 8 -p none -s 1 -f none --log --log-file /var/log/oob/sw1.log /dev/x" ]
}

@test "tio logging: 2.6+ and 3.x also append" {
    export OOB_LOG_DIR=/var/log/oob
    for v in "tio v2.6" "tio v3.8" "tio v12.0"; do
        export FAKE_TIO_VERSION="$v"
        run lib _oob_tio_command sw1 /dev/x 115200 8 none 1 none
        [ "$output" = "tio -b 115200 -d 8 -p none -s 1 -f none --log --log-file /var/log/oob/sw1.log --log-append /dev/x" ]
    done
}

@test "tio logging: unreadable version falls back to --log --log-file" {
    export FAKE_TIO_VERSION="garbage" OOB_LOG_DIR=/var/log/oob
    run lib _oob_tio_command sw1 /dev/x 115200 8 none 1 none
    [[ "$output" == *"--log --log-file /var/log/oob/sw1.log /dev/x" ]]
    [[ "$output" != *"--log-append"* ]]
}

# --- runtime dir / tmux config ----------------------------------------------

@test "runtime dir: uses OOB_RUNTIME_DIR when it is ours" {
    run lib oob_runtime_dir
    [ "$output" = "$OOB_RUNTIME_DIR" ]
    [ -d "$OOB_RUNTIME_DIR" ]
}

@test "runtime dir: never uses a symlink, falls back to a private mktemp dir" {
    mkdir "$TEST_TMP/elsewhere"
    ln -s "$TEST_TMP/elsewhere" "$OOB_RUNTIME_DIR"
    run lib oob_runtime_dir
    [ "$output" != "$OOB_RUNTIME_DIR" ]
    [[ "$output" == "$TEST_TMP"/oob-usb-serial.* ]]
    [ "$(stat -c %a "$output")" = "700" ]
}

@test "tmux config keeps closed consoles and binds respawn" {
    run bash "$SRC/lib/session-gen.sh"
    [[ "$output" == *"set -g remain-on-exit on"* ]]
    [[ "$output" == *"bind R respawn-window"* ]]
}
