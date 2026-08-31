#!/usr/bin/env bash
#
# build-apt-repo.sh - assemble and sign a Debian APT repository.
#
# Produces a signed, flat-per-suite APT archive under an output directory that
# can be served over HTTPS (e.g. GitHub Pages). Structure:
#
#   <out>/
#     pubkey.gpg                         (public signing key, for users)
#     pool/main/o/oob-usb-serial/*.deb   (all package versions)
#     dists/<suite>/Release              (signed inline as InRelease)
#     dists/<suite>/InRelease
#     dists/<suite>/Release.gpg
#     dists/<suite>/main/binary-all/Packages{,.gz}
#
# Usage:
#   scripts/build-apt-repo.sh --pool <dir-with-debs> --out <output-dir> \
#       [--suite stable] [--origin oob-usb-serial] [--pubkey docs/apt/pubkey.gpg]
#
# Signing:
#   Requires a GPG secret key already imported into the current GNUPGHOME.
#   The CI workflow imports APT_GPG_PRIVATE_KEY before calling this script.
#   Set APT_GPG_KEYID to select the key; otherwise the first secret key is used.

set -o errexit
set -o nounset
set -o pipefail

SUITE="stable"
COMPONENT="main"
ARCH="all"
ORIGIN="oob-usb-serial"
LABEL="oob-usb-serial"
POOL_SRC=""
OUT=""
PUBKEY_SRC="docs/apt/pubkey.gpg"

die() { printf 'build-apt-repo: %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --pool)    POOL_SRC="$2"; shift 2 ;;
        --out)     OUT="$2"; shift 2 ;;
        --suite)   SUITE="$2"; shift 2 ;;
        --origin)  ORIGIN="$2"; shift 2 ;;
        --label)   LABEL="$2"; shift 2 ;;
        --pubkey)  PUBKEY_SRC="$2"; shift 2 ;;
        *) die "unknown argument: $1" ;;
    esac
done

[ -n "$POOL_SRC" ] || die "--pool is required"
[ -n "$OUT" ] || die "--out is required"
command -v apt-ftparchive >/dev/null 2>&1 || die "apt-ftparchive not found (install apt-utils)"
command -v gpg >/dev/null 2>&1 || die "gpg not found"

# Resolve the signing key id.
KEYID="${APT_GPG_KEYID:-}"
if [ -z "$KEYID" ]; then
    KEYID="$(gpg --list-secret-keys --with-colons | awk -F: '/^sec:/{print $5; exit}')"
fi
[ -n "$KEYID" ] || die "no GPG secret key available to sign with"

POOL_DIR="${OUT}/pool/${COMPONENT}/o/oob-usb-serial"
DIST_DIR="${OUT}/dists/${SUITE}/${COMPONENT}/binary-${ARCH}"

rm -rf "$OUT"
mkdir -p "$POOL_DIR" "$DIST_DIR"

# Collect all .deb files into the pool.
found=0
for deb in "$POOL_SRC"/*.deb; do
    [ -e "$deb" ] || continue
    cp -f "$deb" "$POOL_DIR/"
    found=1
done
[ "$found" -eq 1 ] || die "no .deb files found in $POOL_SRC"

# Generate the Packages index (paths are relative to $OUT).
(
    cd "$OUT"
    apt-ftparchive packages "pool/${COMPONENT}" > "dists/${SUITE}/${COMPONENT}/binary-${ARCH}/Packages"
    gzip -9c "dists/${SUITE}/${COMPONENT}/binary-${ARCH}/Packages" \
        > "dists/${SUITE}/${COMPONENT}/binary-${ARCH}/Packages.gz"
)

# Generate the Release file for the suite.
cat > "${OUT}/dists/${SUITE}/Release" <<EOF
Origin: ${ORIGIN}
Label: ${LABEL}
Suite: ${SUITE}
Codename: ${SUITE}
Architectures: ${ARCH}
Components: ${COMPONENT}
Description: APT repository for oob-usb-serial
EOF

(
    cd "${OUT}/dists/${SUITE}"
    apt-ftparchive release . >> Release
)

# Sign: detached (Release.gpg) and inline (InRelease).
gpg --default-key "$KEYID" --batch --yes -abs \
    -o "${OUT}/dists/${SUITE}/Release.gpg" "${OUT}/dists/${SUITE}/Release"
gpg --default-key "$KEYID" --batch --yes --clearsign \
    -o "${OUT}/dists/${SUITE}/InRelease" "${OUT}/dists/${SUITE}/Release"

# Publish the public key alongside the archive for convenience.
if [ -f "$PUBKEY_SRC" ]; then
    cp -f "$PUBKEY_SRC" "${OUT}/pubkey.gpg"
else
    gpg --armor --export "$KEYID" > "${OUT}/pubkey.gpg"
fi

printf 'build-apt-repo: signed archive ready in %s (suite=%s, key=%s)\n' \
    "$OUT" "$SUITE" "$KEYID"
