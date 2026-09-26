# packages/gnucommon.sh — base class for plain GNU FTP autotools packages.
#
# Everything about them follows from the package name, so a GNU package script
# is usually three lines. Set MPKG_GNU_MIRROR (in the environment or in the
# package) to build from a closer mirror.

mpkg_inherit srccommon

MPKG_KIND="gnu"
: "${MPKG_GNU_MIRROR:=https://ftp.kaist.ac.kr/gnu}"

# Runs after the package body, so anything the body set explicitly wins.
mpkg_describe() {
    if [[ -z "${MPKG_LISTING_URL}" ]]; then
        MPKG_LISTING_URL="${MPKG_GNU_MIRROR}/${MPKG_NAME}/"
    fi
    if [[ -z "${MPKG_TAG_PATTERN}" ]]; then
        # Match the tarball, not a bare tag: GNU listings also carry
        # -rc / -alpha archives and .sig files.
        MPKG_TAG_PATTERN="${MPKG_NAME}"'-[0-9]+\.[0-9]+(\.[0-9]+)?\.tar\.gz'
    fi
    if [[ -z "${MPKG_TARBALL_URL}" ]]; then
        MPKG_TARBALL_URL="${MPKG_GNU_MIRROR}/${MPKG_NAME}/"'${tag}.tar.gz'
    fi
}
