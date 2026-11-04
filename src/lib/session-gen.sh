#!/usr/bin/env bash
#
# oob-usb-serial: session generator (tio + tmux)
#
# Combines live discovery with the user's device configuration to build a
# detached tmux session with one window per USB serial adapter, each window
# running tio on the adapter's stable /dev/serial path.
#
# Config-driven behaviour:
#   * Devices are matched by their stable udev ID_SERIAL and/or the physical
#     USB port (/dev/serial/by-path), NOT by /dev/ttyUSBx.
#   * A matched device uses the configured name and serial line settings.
#   * An unmatched device falls back to the global defaults and an
#     auto-generated name derived from its model/serial.
#   * With an empty config, every discovered adapter opens at the defaults.
#
# devices.conf format (INI; '#' and ';' comments allowed):
#   Each [section] defines one device; the section name is the tmux window
#   title. Keys (match and/or path required, the rest optional):
#     match   shell glob matched against udev ID_SERIAL (e.g. *FT232R*)
#     path    shell glob matched against the /dev/serial/by-path link (full
#             path or its basename), i.e. the physical USB port
#     baud    baud rate (default OOB_DEFAULT_BAUD)
#     data    data bits 5|6|7|8 (default OOB_DEFAULT_DATA)
#     parity  none|odd|even (default OOB_DEFAULT_PARITY)
#     stop    1|2 (default OOB_DEFAULT_STOP)
#     flow    none|soft|hard (default OOB_DEFAULT_FLOW)
#   When both match and path are set, both must fit. Sections are evaluated in
#   file order; the first one that fits wins.

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
# Reduce a window name to [A-Za-z0-9_.-]: safe as a tmux window name and as a
# log file name (no '/', ':' or whitespace).
_oob_sanitize_name() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_' | sed 's/__*/_/g; s/^_//; s/_$//'
}

# ---------------------------------------------------------------------------
# Serial setting validation (tio vocabulary). Each returns 0 when valid.
# ---------------------------------------------------------------------------
_oob_valid_baud()   { [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]; }
_oob_valid_data()   { case "${1:-}" in 5|6|7|8) return 0 ;; esac; return 1; }
_oob_valid_parity() { case "${1:-}" in none|odd|even) return 0 ;; esac; return 1; }
_oob_valid_stop()   { case "${1:-}" in 1|2) return 0 ;; esac; return 1; }
_oob_valid_flow()   { case "${1:-}" in none|soft|hard) return 0 ;; esac; return 1; }

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

# _oob_lookup_config <id_serial> [by-path]
# Echoes "<name>|<baud>|<data>|<parity>|<stop>|<flow>" for the first matching
# section, or nothing. Omitted keys fall back to the OOB_DEFAULT_* values.
_oob_lookup_config() {
    local id_serial="$1" bypath="${2:-}"
    [ -f "$OOB_DEVICES_CONF" ] || return 0

    local line key val
    local sec_name="" sec_match="" sec_path=""
    local sec_baud="" sec_data="" sec_parity="" sec_stop="" sec_flow=""

    _oob_emit_if_match() {
        [ -n "$sec_name" ] || return 1
        [ -n "$sec_match" ] || [ -n "$sec_path" ] || return 1
        # shellcheck disable=SC2254  # intentional glob match
        if [ -n "$sec_match" ]; then
            case "$id_serial" in
                $sec_match) ;;
                *) return 1 ;;
            esac
        fi
        if [ -n "$sec_path" ]; then
            [ -n "$bypath" ] || return 1
            # shellcheck disable=SC2254  # intentional glob match
            case "$bypath" in
                $sec_path) ;;
                *) case "${bypath##*/}" in
                       $sec_path) ;;
                       *) return 1 ;;
                   esac ;;
            esac
        fi
        printf '%s|%s|%s|%s|%s|%s' \
            "$sec_name" \
            "${sec_baud:-$OOB_DEFAULT_BAUD}" \
            "${sec_data:-$OOB_DEFAULT_DATA}" \
            "${sec_parity:-$OOB_DEFAULT_PARITY}" \
            "${sec_stop:-$OOB_DEFAULT_STOP}" \
            "${sec_flow:-$OOB_DEFAULT_FLOW}"
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
                sec_match="" ; sec_path=""
                sec_baud="" ; sec_data="" ; sec_parity="" ; sec_stop="" ; sec_flow=""
                ;;
            *=*)
                key="$(_oob_trim "${line%%=*}")"
                val="$(_oob_trim "${line#*=}")"
                case "$key" in
                    match)  sec_match="$val" ;;
                    path)   sec_path="$val" ;;
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

# _oob_dup_serials <raw>
# Print each ID_SERIAL that more than one discovered adapter reports.
_oob_dup_serials() {
    printf '%s\n' "$1" | awk -F '\t' 'NF { c[$2]++ } END { for (s in c) if (c[s] > 1) print s }'
}

# _oob_pick_target <by-id> <by-path> <devnode> <ambiguous:0|1>
# The device path tio should open. by-id follows the adapter across replugs,
# but adapters sharing an ID_SERIAL also share (and fight over) one by-id
# link, so those use by-path (the physical port) instead.
_oob_pick_target() {
    local byid="$1" bypath="$2" devnode="$3" ambiguous="$4"
    if [ "$ambiguous" = "1" ] && [ -n "$bypath" ]; then
        printf '%s' "$bypath"
    elif [ -n "$byid" ] && [ "$byid" != "$devnode" ]; then
        printf '%s' "$byid"
    elif [ -n "$bypath" ]; then
        printf '%s' "$bypath"
    else
        printf '%s' "$devnode"
    fi
}

# _oob_auto_name <model> <id_serial> <by-path> <ambiguous:0|1>
# Window name for an adapter that has no devices.conf section.
_oob_auto_name() {
    local model="$1" id_serial="$2" bypath="$3" ambiguous="$4" name
    name="$(_oob_sanitize_name "${model:-serial}_${id_serial}")"
    name="${name:0:24}"
    if [ "$ambiguous" = "1" ] && [ -n "$bypath" ]; then
        # Disambiguate by physical port, e.g. "...-usb-0:1.3:1.0-port0" -> "1.3:1.0"
        local port
        port="$(printf '%s' "${bypath##*/}" | sed -n 's/.*usb[^-]*-[0-9]*:\([0-9.:]*\).*/\1/p')"
        [ -n "$port" ] && name="${name}_$(_oob_sanitize_name "$port")"
    fi
    printf '%s' "${name:-console}"
}

# oob_resolve [raw]
# Resolve every discovered adapter (from <raw>, or a fresh discovery) against
# devices.conf. Prints one tab-separated record per adapter:
#   name, baud, data, parity, stop, flow, target, devnode, id_serial,
#   mapped (yes|no), by-path
# by-path is last because it may be empty: tab is IFS whitespace, so an empty
# field in the middle would collapse when read back with `read`.
# Names are sanitized and made unique (-2, -3, ...). Invalid settings fall
# back to the global defaults with a warning on stderr.
oob_resolve() {
    local raw
    if [ "$#" -gt 0 ]; then raw="$1"; else raw="$(oob_discover_raw)"; fi
    [ -n "$raw" ] || return 0

    local dups
    dups="$(_oob_dup_serials "$raw")"

    local -A used=()
    local devnode id_serial vendor model byid bypath
    local cfg name baud data parity stop flow mapped ambiguous target base n
    while IFS=$'\t' read -r devnode id_serial vendor model byid bypath; do
        [ -n "${devnode:-}" ] || continue
        : "$vendor"

        ambiguous=0
        if [ -n "$dups" ] && printf '%s\n' "$dups" | grep -Fxq -- "$id_serial"; then
            ambiguous=1
        fi

        cfg="$(_oob_lookup_config "$id_serial" "$bypath")"
        if [ -n "$cfg" ]; then
            IFS='|' read -r name baud data parity stop flow <<< "$cfg"
            name="$(_oob_sanitize_name "$name")"
            mapped=yes
        else
            name="$(_oob_auto_name "$model" "$id_serial" "$bypath" "$ambiguous")"
            baud="$OOB_DEFAULT_BAUD"; data="$OOB_DEFAULT_DATA"
            parity="$OOB_DEFAULT_PARITY"; stop="$OOB_DEFAULT_STOP"; flow="$OOB_DEFAULT_FLOW"
            mapped=no
        fi
        [ -n "$name" ] || name="console"

        _oob_valid_baud "$baud" \
            || { _oob_gen_err "warning: ${name}: invalid baud '${baud}', using ${OOB_DEFAULT_BAUD}"; baud="$OOB_DEFAULT_BAUD"; }
        _oob_valid_data "$data" \
            || { _oob_gen_err "warning: ${name}: invalid data '${data}', using ${OOB_DEFAULT_DATA}"; data="$OOB_DEFAULT_DATA"; }
        _oob_valid_parity "$parity" \
            || { _oob_gen_err "warning: ${name}: invalid parity '${parity}', using ${OOB_DEFAULT_PARITY}"; parity="$OOB_DEFAULT_PARITY"; }
        _oob_valid_stop "$stop" \
            || { _oob_gen_err "warning: ${name}: invalid stop '${stop}', using ${OOB_DEFAULT_STOP}"; stop="$OOB_DEFAULT_STOP"; }
        _oob_valid_flow "$flow" \
            || { _oob_gen_err "warning: ${name}: invalid flow '${flow}', using ${OOB_DEFAULT_FLOW}"; flow="$OOB_DEFAULT_FLOW"; }

        base="$name"; n=2
        while [ -n "${used[$name]:-}" ]; do
            name="${base}-${n}"; n=$((n + 1))
        done
        used[$name]=1

        target="$(_oob_pick_target "$byid" "$bypath" "$devnode" "$ambiguous")"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$name" "$baud" "$data" "$parity" "$stop" "$flow" \
            "$target" "$devnode" "$id_serial" "$mapped" "$bypath"
    done <<< "$raw"
}

# _oob_tio_version
# Print tio's "<major> <minor>" (e.g. "2 5"), or nothing if it can't be read.
# Cached in _OOB_TIO_VERSION; call once outside a subshell to fill the cache.
_oob_tio_version() {
    if [ -z "${_OOB_TIO_VERSION+x}" ]; then
        _OOB_TIO_VERSION="$( { tio --version 2>/dev/null || true; } \
            | sed -n '1s/^[^0-9]*\([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p')"
    fi
    printf '%s' "$_OOB_TIO_VERSION"
}

# _oob_tio_log_args <file>
# tio's logging flags differ by version:
#   1.x        -l <file>
#   2.0 - 2.5  --log --log-file <file>          (here -l is a bare --log)
#   2.6+, 3.x  --log --log-file <file> --log-append
# An unreadable version gets the 2.x form, which current releases accept.
_oob_tio_log_args() {
    local file="$1" ver major minor
    ver="$(_oob_tio_version)"
    read -r major minor <<< "${ver:-0 0}"
    if [ "$major" -eq 1 ]; then
        printf -- '-l %q' "$file"
    elif [ "$major" -gt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -ge 6 ]; }; then
        printf -- '--log --log-file %q --log-append' "$file"
    else
        printf -- '--log --log-file %q' "$file"
    fi
}

# _oob_tio_command <name> <target> <baud> <data> <parity> <stop> <flow>
# Print a safely-quoted tio command line for one adapter. When OOB_LOG_DIR is
# set, add per-console logging to <dir>/<name>.log.
_oob_tio_command() {
    local name="$1" target="$2" baud="$3" data="$4" parity="$5" stop="$6" flow="$7"
    local cmd
    cmd="tio -b $(printf '%q' "$baud") -d $(printf '%q' "$data")"
    cmd="$cmd -p $(printf '%q' "$parity") -s $(printf '%q' "$stop")"
    cmd="$cmd -f $(printf '%q' "$flow")"
    if [ -n "$OOB_LOG_DIR" ]; then
        cmd="$cmd $(_oob_tio_log_args "${OOB_LOG_DIR%/}/${name}.log")"
    fi
    cmd="$cmd $(printf '%q' "$target")"
    printf '%s' "$cmd"
}

# oob_runtime_dir
# A private directory for the generated tmux config. Uses OOB_RUNTIME_DIR
# (/run/oob-usb-serial, prepared by root for OOB_USER) when it is a directory
# owned by the caller; otherwise a fresh mktemp directory (prints its path;
# the caller removes it).
oob_runtime_dir() {
    local dir="${OOB_RUNTIME_DIR:-/run/oob-usb-serial}"
    if [ ! -e "$dir" ]; then
        mkdir -m 0700 "$dir" 2>/dev/null || true
    fi
    if [ -d "$dir" ] && [ ! -L "$dir" ] && [ -O "$dir" ] && [ -w "$dir" ]; then
        printf '%s' "$dir"
        return 0
    fi
    mktemp -d "${TMPDIR:-/tmp}/oob-usb-serial.XXXXXX"
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
