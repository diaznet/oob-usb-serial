# Shared fixtures for the bats suite.
#
# Every test gets a private scratch tree:
#   $TEST_TMP/sys   fake sysfs     (OOB_SYSFS_ROOT)
#   $TEST_TMP/dev   fake /dev      (OOB_DEV_ROOT)
#   $TEST_TMP/bin   fake udevadm + tio, first on PATH
# so nothing touches real devices, the real /etc config or a real tmux server.

# shellcheck disable=SC2034  # REPO_ROOT/SRC/CLI are used by the .bats files
REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
SRC="${REPO_ROOT}/src"
CLI="${SRC}/bin/oob-usb-serial"

common_setup() {
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/oob-test.XXXXXX")"
    mkdir -p "$TEST_TMP/sys/bus/usb/devices/usb1" "$TEST_TMP/dev/serial" \
             "$TEST_TMP/bin" "$TEST_TMP/etc"

    export OOB_SYSFS_ROOT="$TEST_TMP/sys"
    export OOB_DEV_ROOT="$TEST_TMP/dev"
    export OOB_CONF="$TEST_TMP/etc/oob-usb-serial.conf"
    export OOB_DEVICES_CONF="$TEST_TMP/etc/devices.conf"
    export OOB_RUNTIME_DIR="$TEST_TMP/run"
    export OOB_TMUX_SOCKET="oob-test-$$-${BATS_TEST_NUMBER:-0}"
    export TMPDIR="$TEST_TMP"
    export FAKE_TIO_LOG="$TEST_TMP/tio.calls"
    export FAKE_TIO_VERSION="tio v2.5"
    unset TMUX OOB_LIB_DIR

    # Session commands must run as OOB_USER; make that the test user.
    printf 'OOB_USER="%s"\n' "$(id -un)" > "$OOB_CONF"
    : > "$OOB_DEVICES_CONF"

    # Fake udevadm: `udevadm info -q property -p <syspath>` prints the
    # KEY=VALUE file stored next to the fake sysfs node.
    cat > "$TEST_TMP/bin/udevadm" <<'EOF'
#!/usr/bin/env bash
p=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -p) p="$2"; shift 2 ;;
        *)  shift ;;
    esac
done
[ -n "$p" ] && [ -f "$p/props" ] && cat "$p/props"
exit 0
EOF

    # Fake tio: reports $FAKE_TIO_VERSION, logs its argv, then idles like a
    # connected console until tmux kills it.
    cat > "$TEST_TMP/bin/tio" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
    printf '%s\n' "$FAKE_TIO_VERSION"
    exit 0
fi
printf '%s\n' "$*" >> "$FAKE_TIO_LOG"
exec sleep 600
EOF
    chmod +x "$TEST_TMP/bin/udevadm" "$TEST_TMP/bin/tio"
    export PATH="$TEST_TMP/bin:$PATH"
}

common_teardown() {
    tmux -L "$OOB_TMUX_SOCKET" kill-server >/dev/null 2>&1 || true
    rm -rf "$TEST_TMP"
}

# add_device <devname> <id_serial> [model] [by-id name] [by-path name] [subsystem] [class dir]
# Create a fake USB node: sysfs entry + udev properties, the /dev node, and
# optional /dev/serial/by-id and by-path symlinks. Pass "-" to skip a link.
add_device() {
    local devname="$1" serial="$2" model="${3:-FT232R_USB_UART}"
    local byid="${4:--}" bypath="${5:--}" subsystem="${6:-tty}" class="${7:-tty}"
    local node="$OOB_SYSFS_ROOT/bus/usb/devices/usb1/1-1/1-1:1.0/${devname}/${class}/${devname}"
    mkdir -p "$node"
    : > "$node/dev"
    {
        printf 'DEVPATH=/devices/fake/%s\n' "$devname"
        printf 'DEVNAME=/dev/%s\n' "$devname"
        printf 'SUBSYSTEM=%s\n' "$subsystem"
        printf 'ID_SERIAL=%s\n' "$serial"
        printf 'ID_VENDOR=%s\n' "FTDI"
        printf 'ID_MODEL=%s\n' "$model"
    } > "$node/props"

    : > "$OOB_DEV_ROOT/$devname"
    if [ "$byid" != "-" ]; then
        mkdir -p "$OOB_DEV_ROOT/serial/by-id"
        ln -sfn "../../$devname" "$OOB_DEV_ROOT/serial/by-id/$byid"
    fi
    if [ "$bypath" != "-" ]; then
        mkdir -p "$OOB_DEV_ROOT/serial/by-path"
        ln -sfn "../../$devname" "$OOB_DEV_ROOT/serial/by-path/$bypath"
    fi
}

# props_of <devname> — path of a device's fake udev property file.
props_of() {
    printf '%s' "$OOB_SYSFS_ROOT/bus/usb/devices/usb1/1-1/1-1:1.0/$1/tty/$1/props"
}

# refute <command...> — fail when the command succeeds. (`! cmd` does not
# fail a bats test, and `run !` needs bats >= 1.5, newer than Debian 11's.)
refute() {
    if "$@"; then
        printf 'expected failure: %s\n' "$*" >&2
        return 1
    fi
}

# lib <function> [args...] — call a library function in a fresh bash, so the
# library's strict mode never leaks into bats itself.
lib() {
    bash -c '. "$1/lib/session-gen.sh"; shift; "$@"' _ "$SRC" "$@"
}
