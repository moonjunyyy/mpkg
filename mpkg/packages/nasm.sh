mpkg_inherit srccommon

MPKG_TITLE="NASM"
MPKG_DESC="x86 assembler; ffmpeg and x264 need it for their SIMD code"
MPKG_HOMEPAGE="https://www.nasm.us/"
MPKG_REQUIRES_CMD=(cc make)

# Releases live in one directory per version: releasebuilds/3.02/nasm-3.02.tar.gz.
# The listing names directories, not tarballs, so discovery is done here; the
# newest directory with a tarball in it wins (rc builds get their own dirs too).
MPKG_LISTING_URL="https://www.nasm.us/pub/nasm/releasebuilds/"
MPKG_TARBALL_URL='https://www.nasm.us/pub/nasm/releasebuilds/${version}/nasm-${version}.tar.gz'

mpkg_discover() {
    local listing="nasm-listing.html" ver tried=0
    MPKG_TMPFILES+=("${listing}")
    mpkg::download "${MPKG_LISTING_URL}" "${listing}" || return 1
    while IFS= read -r ver; do
        (( tried++ >= MPKG_TAG_CANDIDATES )) && break
        MPKG_VERSION="${ver}"
        MPKG_TAG="nasm-${ver}"
        mpkg::url_exists "$(mpkg::render "${MPKG_TARBALL_URL}")" && return 0
    done < <(grep -oE 'href="[0-9]+\.[0-9]+(\.[0-9]+)?/"' "${listing}" \
             | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | mpkg::vsort -r -u)
    mpkg::err "nasm: no usable release found at ${MPKG_LISTING_URL}"
    return 1
}
