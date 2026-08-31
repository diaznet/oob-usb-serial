#!/usr/bin/env bash
#
# build.sh - build the oob-usb-serial .deb package.
#
# Works on Linux/WSL natively (using dpkg tooling), and on macOS or any host
# with Docker by transparently building inside a Debian container. The GitHub
# Actions pipeline calls this same script on a Linux runner.
#
# Usage:
#   ./build.sh [VERSION]
#
#   VERSION   Optional package version (e.g. 1.2.0). If omitted it is derived
#             from the closest git tag (vX.Y.Z -> X.Y.Z), or falls back to the
#             version already in debian/changelog.
#
# Environment:
#   OOB_FORCE_DOCKER=1   Force the Docker build path even if dpkg-deb exists.
#   OOB_DOCKER_IMAGE     Override the build image (default: debian:bookworm-slim).
#
# Output: dist/oob-usb-serial_<version>_all.deb

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

DOCKER_IMAGE="${OOB_DOCKER_IMAGE:-debian:bookworm-slim}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
err() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# Determine the version to stamp into the package.
# ---------------------------------------------------------------------------
derive_version() {
    if [ "$#" -ge 1 ] && [ -n "${1:-}" ]; then
        printf '%s' "$1"
        return 0
    fi
    # Try a git tag like v1.2.3 -> 1.2.3
    local tag
    if tag="$(git describe --tags --abbrev=0 2>/dev/null)"; then
        printf '%s' "${tag#v}"
        return 0
    fi
    # Fall back to whatever debian/changelog currently declares.
    dpkg-parsechangelog -SVersion 2>/dev/null \
        || sed -n '1s/.*(\(.*\)).*/\1/p' debian/changelog
}

# ---------------------------------------------------------------------------
# Native (Linux/WSL) build path.
# ---------------------------------------------------------------------------
build_native() {
    local version="$1"
    log "Native build (dpkg-buildpackage), version=${version}"

    for tool in dpkg-buildpackage dpkg-parsechangelog fakeroot; do
        command -v "$tool" >/dev/null 2>&1 || {
            err "missing build tool: $tool (install dpkg-dev debhelper fakeroot)"
            return 1
        }
    done

    # Build in a clean copy so the source tree is never mutated and Windows
    # mount permission quirks are avoided. dpkg-buildpackage writes the .deb to
    # the PARENT of the source directory, so give it a dedicated staging root.
    local stage_root src_dir
    stage_root="$(mktemp -d)"
    src_dir="${stage_root}/oob-usb-serial"
    mkdir -p "$src_dir"

    # Copy tracked-relevant files (exclude VCS + build artifacts).
    tar --exclude='./.git' --exclude='./dist' --exclude='./debian/oob-usb-serial' \
        --exclude='./debian/.debhelper' -cf - . | ( cd "$src_dir" && tar -xf - )

    (
        cd "$src_dir"

        # Normalise permissions (Windows mounts mark everything executable).
        chmod -x debian/* 2>/dev/null || true
        chmod +x debian/rules debian/postinst debian/postrm build.sh
        find . -name '*.sh' -exec chmod +x {} +
        chmod +x src/bin/oob-usb-serial

        # Stamp the version: rewrite the top changelog entry if it differs.
        local current
        current="$(dpkg-parsechangelog -SVersion)"
        if [ "$current" != "$version" ]; then
            log "Setting changelog version ${current} -> ${version}"
            DEBEMAIL="${DEBEMAIL:-diaznet@users.noreply.github.com}" \
            DEBFULLNAME="${DEBFULLNAME:-diaznet}" \
            dch --newversion "$version" --distribution unstable \
                --force-bad-version "Release ${version}" 2>/dev/null \
            || sed -i "1s/(${current})/(${version})/" debian/changelog
        fi

        dpkg-buildpackage -us -uc -b
    )

    # The artifact lands in stage_root (the parent of the source dir).
    mkdir -p dist
    local artifact
    artifact="$(find "$stage_root" -maxdepth 1 -name 'oob-usb-serial_*_all.deb' | head -1)"
    if [ -z "$artifact" ]; then
        rm -rf "$stage_root"
        err "build produced no .deb"
        return 1
    fi
    cp "$artifact" dist/
    log "Built: dist/$(basename "$artifact")"
    rm -rf "$stage_root"
}

# ---------------------------------------------------------------------------
# Docker build path (Windows/macOS or forced).
# ---------------------------------------------------------------------------
build_docker() {
    local version="$1"
    command -v docker >/dev/null 2>&1 || {
        err "Docker not found. On Windows/macOS a Docker install is required to build the .deb."
        err "Alternatively build on a Debian/Ubuntu host (or WSL) with dpkg-dev installed."
        return 1
    }
    log "Docker build via ${DOCKER_IMAGE}, version=${version}"

    docker run --rm \
        -v "${REPO_ROOT}:/src" \
        -w /src \
        -e OOB_FORCE_DOCKER=0 \
        -e DEBEMAIL="${DEBEMAIL:-diaznet@users.noreply.github.com}" \
        -e DEBFULLNAME="${DEBFULLNAME:-diaznet}" \
        "$DOCKER_IMAGE" \
        bash -c '
            set -e
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq --no-install-recommends dpkg-dev debhelper fakeroot devscripts >/dev/null
            ./build.sh "'"$version"'"
        '
    log "Built (via Docker): dist/oob-usb-serial_${version}_all.deb"
}

main() {
    local version
    version="$(derive_version "${1:-}")"
    [ -n "$version" ] || { err "could not determine version"; exit 1; }

    if [ "${OOB_FORCE_DOCKER:-0}" = "1" ]; then
        build_docker "$version"
    elif command -v dpkg-buildpackage >/dev/null 2>&1; then
        build_native "$version"
    else
        log "Native dpkg tooling not found; falling back to Docker."
        build_docker "$version"
    fi
}

main "$@"
