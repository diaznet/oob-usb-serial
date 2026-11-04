#!/usr/bin/env bash
#
# oob-usb-serial: discovery library
#
# Enumerates USB serial adapters attached to the system and resolves them to
# their /dev/tty* nodes together with the stable udev ID_SERIAL identifier.
#
# Public functions:
#   oob_discover_raw            -> lines:
#       "<devnode>\t<id_serial>\t<vendor>\t<model>\t<by-id>\t<by-path>"
#   oob_discover_devnodes [pat] -> just the /dev nodes, optionally grep-filtered
#
# <by-id> is the /dev/serial/by-id/* symlink for the adapter (falls back to the
# /dev node when there is none). <by-path> is the /dev/serial/by-path/* symlink
# naming the physical USB port (empty when there is none). by-path is what
# tells apart adapters that report the same ID_SERIAL (clones without a serial
# number, or the ports of one multi-port chip).
#
# Only tty devices are reported: USB disks, HID devices, webcams and other USB
# nodes that also carry an ID_SERIAL are skipped.
#
# Output is sorted by device node so callers get deterministic ordering.
#
# Test hooks (default to the real system):
#   OOB_SYSFS_ROOT   sysfs mount point            (default /sys)
#   OOB_DEV_ROOT     device directory             (default /dev)

set -o errexit
set -o nounset
set -o pipefail

# Print an error to stderr with a consistent prefix.
_oob_err() {
    printf 'oob-usb-serial: %s\n' "$*" >&2
}

# Ensure the tools we depend on exist before we try to use them.
_oob_require_udevadm() {
    if ! command -v udevadm >/dev/null 2>&1; then
        _oob_err "udevadm not found (install systemd-udev / udev)"
        return 1
    fi
}

# _oob_link_for <dir> <devnode>
# Print the symlink in <dir> that resolves to <devnode>, or nothing.
_oob_link_for() {
    local dir="$1" devnode="$2" link target target_real
    [ -d "$dir" ] || return 0
    target_real="$(readlink -f "$devnode" 2>/dev/null || printf '%s' "$devnode")"
    for link in "$dir"/*; do
        [ -L "$link" ] || continue
        target="$(readlink -f "$link" 2>/dev/null || true)"
        if [ "$target" = "$target_real" ]; then
            printf '%s' "$link"
            return 0
        fi
    done
}

# _oob_byid_for <devnode>
# The /dev/serial/by-id/* symlink for <devnode>, or <devnode> itself. tio
# prefers the by-id path so its auto-reconnect follows the physical adapter.
_oob_byid_for() {
    local link
    link="$(_oob_link_for "${OOB_DEV_ROOT:-/dev}/serial/by-id" "$1")"
    printf '%s' "${link:-$1}"
}

# _oob_bypath_for <devnode>
# The /dev/serial/by-path/* symlink for <devnode>, or nothing.
_oob_bypath_for() {
    _oob_link_for "${OOB_DEV_ROOT:-/dev}/serial/by-path" "$1"
}

# _oob_clean_field <value> — tabs/newlines would break the record format.
_oob_clean_field() {
    local v="${1//$'\t'/ }"
    printf '%s' "${v//$'\n'/ }"
}

# oob_discover_raw
#
# Emits one tab-separated record per USB serial device:
#   /dev/ttyUSB0<TAB>FTDI_...<TAB>FTDI<TAB>FT232R_USB_UART<TAB>/dev/serial/by-id/...<TAB>/dev/serial/by-path/...
#
# udev properties are read as plain KEY=VALUE text and never evaluated: their
# values come from USB descriptors, i.e. from whatever device is plugged in.
oob_discover_raw() {
    _oob_require_udevadm || return 1

    local sys_root="${OOB_SYSFS_ROOT:-/sys}" dev_root="${OOB_DEV_ROOT:-/dev}"
    local sysdevpath syspath line key val
    local subsystem devname id_serial vendor model devnode byid bypath
    local records=""

    # Each tty node of a USB adapter sits at .../tty/<name>/dev in sysfs.
    while IFS= read -r sysdevpath; do
        syspath="${sysdevpath%/dev}"

        subsystem="" devname="" id_serial="" vendor="" model=""
        while IFS= read -r line; do
            key="${line%%=*}"
            val="${line#*=}"
            case "$key" in
                SUBSYSTEM) subsystem="$val" ;;
                DEVNAME)   devname="$val" ;;
                ID_SERIAL) id_serial="$val" ;;
                ID_VENDOR) vendor="$val" ;;
                ID_MODEL)  model="$val" ;;
            esac
        done < <(udevadm info -q property -p "$syspath" 2>/dev/null || true)

        [ "$subsystem" = "tty" ] || continue
        [ -n "$devname" ] || continue
        [ -n "$id_serial" ] || continue

        # DEVNAME is absolute (/dev/ttyUSB0); re-root it for the test hook.
        devnode="${dev_root}/${devname#/dev/}"
        byid="$(_oob_byid_for "$devnode")"
        bypath="$(_oob_bypath_for "$devnode")"

        records+="$(_oob_clean_field "$devnode")"$'\t'
        records+="$(_oob_clean_field "$id_serial")"$'\t'
        records+="$(_oob_clean_field "${vendor:-unknown}")"$'\t'
        records+="$(_oob_clean_field "${model:-unknown}")"$'\t'
        records+="$(_oob_clean_field "$byid")"$'\t'
        records+="$(_oob_clean_field "$bypath")"$'\n'
    done < <(find "$sys_root"/bus/usb/devices/usb*/ -path '*/tty/*' -name dev 2>/dev/null)

    # Deterministic ordering by device node.
    printf '%s' "$records" | sort -t $'\t' -k1,1
}

# oob_discover_devnodes [filter]
#
# Prints just the resolved /dev nodes. If a filter is given it is applied
# (case-insensitively) against the whole raw record, so callers can match on
# device node, serial, vendor or model.
oob_discover_devnodes() {
    local filter="${1:-}"
    if [ -z "$filter" ]; then
        oob_discover_raw | awk -F '\t' 'NF{print $1}'
    else
        oob_discover_raw | grep -i -- "$filter" | awk -F '\t' 'NF{print $1}'
    fi
}

# When executed directly (not sourced) behave like a small CLI so the library
# is still useful on its own and easy to test.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-}" in
        -h|--help)
            cat <<'EOF'
Usage: discover.sh [--nodes [FILTER]]

  (no args)          Print full tab-separated records:
                     devnode, id_serial, vendor, model, by-id, by-path
  --nodes [FILTER]   Print only /dev nodes, optionally filtered (case-insensitive)
  -h | --help        Show this help
EOF
            ;;
        --nodes)
            oob_discover_devnodes "${2:-}"
            ;;
        "")
            oob_discover_raw
            ;;
        *)
            _oob_err "unknown argument: $1 (try --help)"
            exit 2
            ;;
    esac
fi
