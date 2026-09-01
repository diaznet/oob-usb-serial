#!/usr/bin/env bash
#
# oob-serial: discovery library
#
# Enumerates USB serial adapters attached to the system and resolves them to
# their /dev/tty* nodes together with the stable udev ID_SERIAL identifier.
#
# This is the hardened successor to the original findusbdev.sh.
#
# Public functions:
#   oob_discover_raw            -> lines:
#       "<devnode>\t<id_serial>\t<vendor>\t<model>\t<by-id-path>"
#   oob_discover_devnodes [pat] -> just the /dev nodes, optionally grep-filtered
#
# The by-id path is the stable /dev/serial/by-id/* symlink for the adapter,
# which follows the physical device across replugs (unlike /dev/ttyUSBx). It
# falls back to the /dev node when no by-id symlink exists.
#
# Output is stable-sorted by device node so callers get deterministic ordering.

set -o errexit
set -o nounset
set -o pipefail

# Print an error to stderr with a consistent prefix.
_oob_err() {
    printf 'oob-serial: %s\n' "$*" >&2
}

# Ensure the tools we depend on exist before we try to use them.
_oob_require_udevadm() {
    if ! command -v udevadm >/dev/null 2>&1; then
        _oob_err "udevadm not found (install systemd-udev / udev)"
        return 1
    fi
}

# _oob_byid_for <devnode>
# Print the /dev/serial/by-id/* symlink that resolves to <devnode>, or the
# devnode itself if none is found. tio prefers the by-id path so its
# auto-reconnect follows the physical adapter across replugs.
_oob_byid_for() {
    local devnode="$1" link target
    local target_real
    target_real="$(readlink -f "$devnode" 2>/dev/null || printf '%s' "$devnode")"
    if [ -d /dev/serial/by-id ]; then
        for link in /dev/serial/by-id/*; do
            [ -e "$link" ] || continue
            target="$(readlink -f "$link" 2>/dev/null || true)"
            if [ "$target" = "$target_real" ]; then
                printf '%s' "$link"
                return 0
            fi
        done
    fi
    printf '%s' "$devnode"
}

# oob_discover_raw
#
# Emits one tab-separated record per USB serial device:
#   /dev/ttyUSB0<TAB>FTDI_...<TAB>FTDI<TAB>FT232R USB UART<TAB>/dev/serial/by-id/...
#
# Bus/hub pseudo-devices and nodes without an ID_SERIAL are skipped, matching
# the intent of the original script but without the fragile eval-in-subshell
# ordering issues.
oob_discover_raw() {
    _oob_require_udevadm || return 1

    local sysdevpath syspath devname
    local records=""

    # Iterate every 'dev' attribute under the USB bus tree. Each corresponds to
    # a character/block device node we can resolve with udevadm.
    while IFS= read -r sysdevpath; do
        syspath="${sysdevpath%/dev}"

        devname="$(udevadm info -q name -p "$syspath" 2>/dev/null || true)"
        [ -z "$devname" ] && continue
        # Skip raw bus endpoints (e.g. bus/usb/001/002).
        case "$devname" in
            bus/*) continue ;;
        esac

        # Pull udev properties into local variables in a subshell so we never
        # pollute the caller's environment via eval.
        # Extract the udev identity fields in a subshell (tab-separated), then
        # assemble the full record in this shell so we can append the by-id
        # path (a local variable the subshell would not see).
        local ident byid
        ident="$(
            eval "$(udevadm info -q property --export -p "$syspath" 2>/dev/null || true)"
            [ -z "${ID_SERIAL:-}" ] && exit 0
            printf '%s\t%s\t%s' \
                "${ID_SERIAL:-unknown}" \
                "${ID_VENDOR:-unknown}" \
                "${ID_MODEL:-unknown}"
        )"
        [ -z "$ident" ] && continue
        byid="$(_oob_byid_for "/dev/${devname}")"
        records+="/dev/${devname}"$'\t'"${ident}"$'\t'"${byid}"$'\n'
    done < <(find /sys/bus/usb/devices/usb*/ -name dev 2>/dev/null)

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
        oob_discover_raw | grep -i "$filter" | awk -F '\t' 'NF{print $1}'
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
                     devnode <TAB> id_serial <TAB> vendor <TAB> model <TAB> by-id
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
