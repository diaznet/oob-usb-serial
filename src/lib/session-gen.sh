#!/usr/bin/env bash
#
# oob-usb-serial: session generator (tio + tmux)
#
# Combines live discovery with the user's device configuration to build a
# detached tmux session with one window per USB serial adapter, each window
# running tio on the adapter's stable /dev/serial/by-id path.
#
# Config-driven behaviour:
#   * Devices are matched by their stable udev ID_SERIAL, NOT by /dev/ttyUSBx.
#   * A matched device uses the configured name and serial line settings.
#   * An unmatched device falls back to the global defaults and an
#     auto-generated name derived from its model/serial.
#   * With an empty config, every discovered adapter opens at the defaults.
#
# devices.conf format (INI; '#' and ';' comments allowed):
#   Each [section] defines one device; the section name is the tmux window
#   title. Keys (all optional except match):
#     match   shell glob matched against udev ID_SERIAL (required, e.g. *FT232R*)
#     baud    baud rate (default OOB_DEFAULT_BAUD)
#     data    data bits 5|6|7|8 (default OOB_DEFAULT_DATA)
#     parity  none|odd|even (default OOB_DEFAULT_PARITY)
#     stop    1|2 (default OOB_DEFAULT_STOP)
#     flow    none|soft|hard (default OOB_DEFAULT_FLOW)
#   Sections are matched in file order; the first matching `match` wins.

set -o errexit
set -o nounset
set -o pipefail

# Resolve the directory this library lives in so we can source discover.sh
# regardless of the caller's working directory.
_OOB_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=discover.sh
. "${_OOB_LIB_DIR}/discover.sh"

# Defaults; overridable via environment (set by the main CLI from config).
: "${OOB_DEFAULT_BAUD:=115200}"
: "${OOB_DEFAULT_DATA:=8}"
: "${OOB_DEFAULT_PARITY:=none}"
: "${OOB_DEFAULT_STOP:=1}"
: "${OOB_DEFAULT_FLOW:=none}"
: "${OOB_SESSION_NAME:=oob}"
: "${OOB_LOG_DIR:=}"
: "${OOB_DEVICES_CONF:=/etc/oob-usb-serial/devices.conf}"

_oob_gen_err() { printf 'oob-usb-serial: %s\n' "$*" >&2; }

# _oob_trim <string> — strip leading/trailing whitespace.
_oob_trim() {
    printf '%s' "${1:-}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# _oob_sanitize_name <string>
# tmux window names should avoid problematic characters; reduce to a compact
# identifier.
_oob_sanitize_name() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_' | sed 's/__*/_/g; s/^_//; s/_$//'
}

# _oob_framing_summary <data> <parity> <stop> <flow>
# Compact human-readable framing, e.g. "8N1" or "8N1/hard". Flow shown only
# when not "none".
_oob_framing_summary() {
    local data="$1" parity="$2" stop="$3" flow="$4" p
    case "$parity" in
        odd)  p="O" ;;
        even) p="E" ;;
        *)    p="N" ;;
    esac
    if [ "$flow" = "none" ]; then
        printf '%s%s%s' "$data" "$p" "$stop"
    else
        printf '%s%s%s/%s' "$data" "$p" "$stop" "$flow"
    fi
}

# _oob_lookup_config <id_serial>
# Echoes "<name>|<baud>|<data>|<parity>|<stop>|<flow>" for the first matching
# device, or nothing. Sections are evaluated in file order; the first whose
# `match` glob matches the given ID_SERIAL wins. The section header becomes the
# window name. Omitted keys fall back to the OOB_DEFAULT_* values.
_oob_lookup_config() {
    local id_serial="$1"
    [ -f "$OOB_DEVICES_CONF" ] || return 0

    local line key val
    local sec_name="" sec_match="" sec_baud="" sec_data="" sec_parity="" sec_stop="" sec_flow=""

    _oob_emit_if_match() {
        [ -n "$sec_name" ] || return 1
        [ -n "$sec_match" ] || return 1
        # shellcheck disable=SC2254  # intentional glob match
        case "$id_serial" in
            $sec_match)
                printf '%s|%s|%s|%s|%s|%s' \
                    "$sec_name" \
                    "${sec_baud:-$OOB_DEFAULT_BAUD}" \
                    "${sec_data:-$OOB_DEFAULT_DATA}" \
                    "${sec_parity:-$OOB_DEFAULT_PARITY}" \
                    "${sec_stop:-$OOB_DEFAULT_STOP}" \
                    "${sec_flow:-$OOB_DEFAULT_FLOW}"
                return 0
                ;;
        esac
        return 1
    }

    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="${line%%;*}"
        line="$(_oob_trim "$line")"
        [ -z "$line" ] && continue

        case "$line" in
            \[*\])
                if _oob_emit_if_match; then
                    return 0
                fi
                sec_name="$(_oob_trim "${line#\[}")"
                sec_name="$(_oob_trim "${sec_name%\]}")"
                sec_match="" ; sec_baud="" ; sec_data="" ; sec_parity="" ; sec_stop="" ; sec_flow=""
                ;;
            *=*)
                key="$(_oob_trim "${line%%=*}")"
                val="$(_oob_trim "${line#*=}")"
                case "$key" in
                    match)  sec_match="$val" ;;
                    baud)   sec_baud="$val" ;;
                    data)   sec_data="$val" ;;
                    parity) sec_parity="$val" ;;
                    stop)   sec_stop="$val" ;;
                    flow)   sec_flow="$val" ;;
                    *) : ;;   # ignore unknown keys (e.g. legacy v1 'framing')
                esac
                ;;
            *) : ;;
        esac
    done < "$OOB_DEVICES_CONF"

    _oob_emit_if_match || true
    return 0
}

# _oob_tio_command <name> <byid> <baud> <data> <parity> <stop> <flow>
# Print a safely-quoted tio command line for one adapter. When OOB_LOG_DIR is
# set, add per-console logging to <dir>/<name>.log.
_oob_tio_command() {
    local name="$1" byid="$2" baud="$3" data="$4" parity="$5" stop="$6" flow="$7"
    local cmd
    cmd="tio -b $(printf '%q' "$baud") -d $(printf '%q' "$data")"
    cmd="$cmd -p $(printf '%q' "$parity") -s $(printf '%q' "$stop")"
    cmd="$cmd -f $(printf '%q' "$flow")"
    if [ -n "$OOB_LOG_DIR" ]; then
        cmd="$cmd -l $(printf '%q' "${OOB_LOG_DIR%/}/${name}.log")"
    fi
    cmd="$cmd $(printf '%q' "$byid")"
    printf '%s' "$cmd"
}

# oob_tmux_config_path — path of the generated tmux config.
oob_tmux_config_path() {
    local dir="${OOB_RUNTIME_DIR:-/run/oob-usb-serial}"
    if mkdir -p "$dir" 2>/dev/null && [ -w "$dir" ]; then
        printf '%s/tmux.conf' "$dir"
    else
        printf '%s/oob-usb-serial-tmux.conf.%s' "${TMPDIR:-/tmp}" "$(id -u)"
    fi
}

# oob_generate_tmux_config > <file>
# Emit the dedicated tmux configuration used for the OOB session. Kept minimal
# and limited to options available in tmux 3.1 (Debian 11).
oob_generate_tmux_config() {
    cat <<'EOF'
# Auto-generated by oob-usb-serial. Do not edit by hand.
set -g remain-on-exit on
set -g mouse on
set -g history-limit 10000
set -g status-left "[ oob-usb-serial ] "
set -g status-right " %Y-%m-%d %H:%M "
setw -g automatic-rename off
setw -g allow-rename off
# Ctrl-b R : relaunch (respawn) the console in the current window after it has
# exited or the device was lost.
bind R respawn-window
EOF
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # When run directly, dump the tmux config (handy for inspection/tests).
    oob_generate_tmux_config
fi
