#!/usr/bin/env bash
#
# oob-usb-serial: screenrc generator
#
# Combines live discovery with the user's device configuration to produce a
# GNU screen configuration that opens one named window per USB serial adapter
# at the correct baud rate and serial framing.
#
# Config-driven behaviour:
#   * Devices are matched by their stable udev ID_SERIAL, NOT by /dev/ttyUSBx,
#     which is not stable across reboots/replugs.
#   * A matched device uses the configured friendly name, baud rate and framing.
#   * An unmatched device falls back to the default baud/framing and an
#     auto-generated name derived from its model/serial.
#   * The tool ships with NO device-specific defaults: with an empty config it
#     simply opens every discovered adapter at the global default settings.
#
# devices.conf format (INI; '#' and ';' comments allowed):
#   Each [section] defines one device; the section name is the screen window
#   title. Keys:
#     match     shell glob matched against udev ID_SERIAL (required, e.g. *FT232R*)
#     baud      baud rate, e.g. 9600, 115200 (optional -> OOB_DEFAULT_SPEED)
#     framing   comma-separated stty options (optional -> OOB_DEFAULT_FRAMING),
#               e.g. "cs8,-parenb,-cstopb" (8N1) or "cs7,parenb,cstopb"
#   Sections are matched in file order; the first matching `match` wins.
#
# Example:
#   [corefw]
#   match   = *FT232R*_A5069RR4
#   baud    = 9600
#   framing = cs8,-parenb,-cstopb
#
#   [edgesw]
#   match   = *Prolific*
#   baud    = 38400
#   framing = cs8,parenb,cstopb,crtsctss

set -o errexit
set -o nounset
set -o pipefail

# Resolve the directory this library lives in so we can source discover.sh
# regardless of the caller's working directory.
_OOB_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=discover.sh
. "${_OOB_LIB_DIR}/discover.sh"

# Defaults; overridable via environment (set by the main CLI from config).
: "${OOB_DEFAULT_SPEED:=9600}"
: "${OOB_DEFAULT_FRAMING:=cs8,-parenb,-cstopb}"
: "${OOB_SESSION_NAME:=oob}"
: "${OOB_DEVICES_CONF:=/etc/oob-usb-serial/devices.conf}"

_oob_gen_err() { printf 'oob-usb-serial: %s\n' "$*" >&2; }

# _oob_sanitize_name <string>
# screen window titles must not contain problematic characters; reduce to a
# safe, compact identifier.
_oob_sanitize_name() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_' | sed 's/__*/_/g; s/^_//; s/_$//'
}

# _oob_framing_to_stty <framing>
# Convert the comma-separated framing spec into space-separated stty arguments.
# Empty input yields empty output (caller then applies the default).
_oob_framing_to_stty() {
    printf '%s' "${1:-}" | tr ',' ' '
}

# _oob_trim <string>
# Strip leading/trailing whitespace.
_oob_trim() {
    printf '%s' "${1:-}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# _oob_lookup_config <id_serial>
# Echoes "<name>|<baud>|<framing>" for the first matching device, or nothing.
#
# The device configuration is an INI file. Each [section] header names a screen
# window; the section's keys describe how to match and open the device:
#
#   [corefw]
#   match   = *FT232R*_A5069RR4      # glob against udev ID_SERIAL (required)
#   baud    = 9600                   # optional -> OOB_DEFAULT_SPEED
#   framing = cs8,-parenb,-cstopb    # optional -> OOB_DEFAULT_FRAMING
#
# Sections are evaluated in file order and the first whose `match` glob matches
# the given ID_SERIAL wins. The section header becomes the window name.
_oob_lookup_config() {
    local id_serial="$1"
    [ -f "$OOB_DEVICES_CONF" ] || return 0

    local line key val
    local sec_name="" sec_match="" sec_baud="" sec_framing=""

    # Emit the currently-accumulated section if its match glob fits; returns 0
    # (and prints) on a hit so the caller can stop.
    _oob_emit_if_match() {
        [ -n "$sec_name" ] || return 1
        [ -n "$sec_match" ] || return 1
        local baud="$sec_baud" framing="$sec_framing"
        [ -z "$baud" ] && baud="$OOB_DEFAULT_SPEED"
        [ -z "$framing" ] && framing="$OOB_DEFAULT_FRAMING"
        # shellcheck disable=SC2254  # intentional glob match
        case "$id_serial" in
            $sec_match)
                printf '%s|%s|%s' "$sec_name" "$baud" "$framing"
                return 0
                ;;
        esac
        return 1
    }

    while IFS= read -r line || [ -n "$line" ]; do
        # Strip inline comments (# or ;) and surrounding whitespace.
        line="${line%%#*}"
        line="${line%%;*}"
        line="$(_oob_trim "$line")"
        [ -z "$line" ] && continue

        case "$line" in
            \[*\])
                # New section header: test the previous section first.
                if _oob_emit_if_match; then
                    return 0
                fi
                sec_name="$(_oob_trim "${line#\[}")"
                sec_name="$(_oob_trim "${sec_name%\]}")"
                sec_match="" ; sec_baud="" ; sec_framing=""
                ;;
            *=*)
                key="$(_oob_trim "${line%%=*}")"
                val="$(_oob_trim "${line#*=}")"
                case "$key" in
                    match)   sec_match="$val" ;;
                    baud)    sec_baud="$val" ;;
                    framing) sec_framing="$val" ;;
                    *) : ;;   # ignore unknown keys
                esac
                ;;
            *) : ;;   # ignore malformed lines
        esac
    done < "$OOB_DEVICES_CONF"

    # Test the final section after EOF.
    if _oob_emit_if_match; then
        return 0
    fi
    return 0
}

# oob_generate_screenrc
# Writes a complete screenrc to stdout. Returns 2 if no serial devices were
# discovered so callers can warn instead of launching an empty session.
#
# For each device we:
#   1. Emit a comment describing the physical device.
#   2. Pre-apply the framing to the tty via `stty` (screen sets the baud, but
#      screen cannot set parity/stop/flow, so stty handles the full framing).
#   3. Open a named screen window bound to the device at the chosen baud.
oob_generate_screenrc() {
    local raw
    raw="$(oob_discover_raw)"

    cat <<'EOF'
# ----------------------------------------------------------------------------
# Auto-generated by oob-usb-serial. Do not edit by hand; regenerate with:
#   oob-usb-serial config --generate
# ----------------------------------------------------------------------------
# Sensible defaults for a serial console multiplexer.
defscrollback 10000
startup_message off
autodetach on
# A readable status line listing all open console windows.
hardstatus alwayslastline
hardstatus string '%{= kG}[ %{G}oob-usb-serial %{g}][%= %{= kw}%?%-Lw%?%{r}(%{W}%n*%f%t%?(%u)%?%{r})%{w}%?%+Lw%?%?%= %{g}][%{B}%Y-%m-%d %{W}%c %{g}]'
EOF

    if [ -z "$raw" ]; then
        printf '# WARNING: no USB serial adapters discovered at generation time.\n'
        _oob_gen_err "no USB serial adapters discovered"
        return 2
    fi

    local devnode id_serial vendor model cfg name baud framing stty_args
    while IFS=$'\t' read -r devnode id_serial vendor model; do
        [ -z "${devnode:-}" ] && continue

        cfg="$(_oob_lookup_config "$id_serial")"
        if [ -n "$cfg" ]; then
            IFS='|' read -r name baud framing <<< "$cfg"
        else
            # Fall back to a name derived from model+serial and default settings.
            name="$(_oob_sanitize_name "${model:-serial}_${id_serial}")"
            name="${name:0:24}"   # keep auto names reasonably short
            baud="$OOB_DEFAULT_SPEED"
            framing="$OOB_DEFAULT_FRAMING"
        fi

        stty_args="$(_oob_framing_to_stty "$framing")"

        printf '\n# %s (serial=%s vendor=%s model=%s)\n' \
            "$devnode" "$id_serial" "$vendor" "$model"
        # Apply full framing up front; screen then attaches at the baud rate.
        if [ -n "$stty_args" ]; then
            printf 'exec /bin/sh -c "stty -F %s %s %s"\n' "$devnode" "$baud" "$stty_args"
        fi
        printf 'screen -t "%s" %s %s\n' "$name" "$devnode" "$baud"
    done <<< "$raw"

    # Land on the first window when attaching.
    printf '\nselect 0\n'
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    oob_generate_screenrc
fi
