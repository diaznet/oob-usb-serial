#!/usr/bin/env bats
# Session lifecycle against a real tmux server (private socket) with a fake
# tio, plus the user check.

load helpers

setup() {
    common_setup
    command -v tmux >/dev/null || skip "tmux not installed"
}
teardown() { common_teardown; }

windows() { tmux -L "$OOB_TMUX_SOCKET" list-windows -t oob -F '#{window_name}'; }

# wait_for_tio <count> — the fake tio logs one line per started console.
wait_for_tio() {
    local i
    for i in $(seq 1 50); do
        [ "$(wc -l < "$FAKE_TIO_LOG" 2>/dev/null || echo 0)" -ge "$1" ] && return 0
        sleep 0.1
    done
    return 1
}

@test "start opens one window per adapter running tio on its stable path" {
    add_device ttyUSB0 FTDI_A1 FT232R usb-FTDI_A1-if00-port0
    add_device ttyUSB1 FTDI_B2 FT232R usb-FTDI_B2-if00-port0
    printf '[core-sw]\nmatch = FTDI_A1\nbaud = 9600\n' > "$OOB_DEVICES_CONF"

    run "$CLI" start
    [ "$status" -eq 0 ]
    [[ "$output" == *"with 2 console(s)"* ]]
    [ "$(windows | tr '\n' ' ')" = "core-sw FT232R_FTDI_B2 " ]

    wait_for_tio 2
    grep -qx -- "-b 9600 -d 8 -p none -s 1 -f none $OOB_DEV_ROOT/serial/by-id/usb-FTDI_A1-if00-port0" "$FAKE_TIO_LOG"
    grep -qx -- "-b 115200 -d 8 -p none -s 1 -f none $OOB_DEV_ROOT/serial/by-id/usb-FTDI_B2-if00-port0" "$FAKE_TIO_LOG"
}

@test "start writes the tmux config into the runtime dir" {
    add_device ttyUSB0 FTDI_A1
    run "$CLI" start
    [ "$status" -eq 0 ]
    grep -q 'remain-on-exit on' "$OOB_RUNTIME_DIR/tmux.conf"
    [ "$(tmux -L "$OOB_TMUX_SOCKET" show-options -gv remain-on-exit)" = "on" ]
}

@test "start falls back to a temporary runtime dir and cleans it up" {
    add_device ttyUSB0 FTDI_A1
    mkdir "$TEST_TMP/other"
    ln -s "$TEST_TMP/other" "$OOB_RUNTIME_DIR"
    run "$CLI" start
    [ "$status" -eq 0 ]
    [ "$(tmux -L "$OOB_TMUX_SOCKET" show-options -gv remain-on-exit)" = "on" ]
    [ -z "$(find "$TEST_TMP" -maxdepth 1 -name 'oob-usb-serial.*')" ]
    [ ! -e "$TEST_TMP/other/tmux.conf" ]
}

@test "start with logging passes version-appropriate tio flags" {
    add_device ttyUSB0 FTDI_A1 FT232R usb-FTDI_A1-if00-port0
    printf 'OOB_USER="%s"\nOOB_LOG_DIR="%s"\n' "$(id -un)" "$TEST_TMP/logs" > "$OOB_CONF"
    export FAKE_TIO_VERSION="tio v1.32"
    run "$CLI" start
    [ "$status" -eq 0 ]
    [ -d "$TEST_TMP/logs" ]
    wait_for_tio 1
    grep -q -- "-l $TEST_TMP/logs/FT232R_FTDI_A1.log " "$FAKE_TIO_LOG"
}

@test "start refuses an empty session" {
    run "$CLI" start
    [ "$status" -eq 1 ]
    [[ "$output" == *"no adapters discovered"* ]]
    run "$CLI" status
    [ "$status" -eq 3 ]
}

@test "start is idempotent; status, stop and restart" {
    add_device ttyUSB0 FTDI_A1
    run "$CLI" start;  [ "$status" -eq 0 ]
    run "$CLI" start;  [ "$status" -eq 0 ]; [[ "$output" == *"already running"* ]]

    run "$CLI" status
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "session 'oob': running" ]]

    add_device ttyUSB1 FTDI_B2
    run "$CLI" restart; [ "$status" -eq 0 ]
    [ "$(windows | wc -l)" -eq 2 ]

    run "$CLI" stop;   [ "$status" -eq 0 ]
    run "$CLI" status; [ "$status" -eq 3 ]
    run "$CLI" stop;   [ "$status" -eq 0 ]; [[ "$output" == *"not running"* ]]
}

@test "list shows resolved names, framing and the path tio opens" {
    add_device ttyUSB0 FTDI_A1 FT232R usb-FTDI_A1-if00-port0
    printf '[core-sw]\nmatch = FTDI_A1\nparity = even\nflow = hard\n' > "$OOB_DEVICES_CONF"
    run "$CLI" list
    [ "$status" -eq 0 ]
    [[ "${lines[2]}" == core-sw*conf*ttyUSB0*115200*8E1/hard*FTDI_A1 ]]
    [[ "${lines[3]}" == *"opens: $OOB_DEV_ROOT/serial/by-id/usb-FTDI_A1-if00-port0" ]]
}

@test "session commands refuse a caller that is not OOB_USER" {
    [ "$(id -u)" -ne 0 ] || skip "root would re-exec as OOB_USER"
    add_device ttyUSB0 FTDI_A1
    printf 'OOB_USER="root"\n' > "$OOB_CONF"
    run "$CLI" start
    [ "$status" -eq 1 ]
    [[ "$output" == *"run this as 'root'"* ]]
}

@test "session commands report a missing OOB_USER" {
    printf 'OOB_USER="no-such-user-oob"\n' > "$OOB_CONF"
    run "$CLI" status
    [ "$status" -eq 1 ]
    [[ "$output" == *"user 'no-such-user-oob' does not exist"* ]]
}

@test "unknown commands exit 2 with usage" {
    run "$CLI" frobnicate
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: oob-usb-serial"* ]]
}
