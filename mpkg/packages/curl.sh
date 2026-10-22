mpkg_inherit srccommon

MPKG_TITLE="cURL"
MPKG_DESC="Command line HTTP client and libcurl"
MPKG_HOMEPAGE="https://curl.se/"
MPKG_PROBE_CMD="curl"
MPKG_DEPENDS=(openssl)
MPKG_REQUIRES_CMD=(cc make)

MPKG_LISTING_URL="https://github.com/curl/curl/tags"
# curl's git tags use underscores (curl-8_22_0) while its tarballs use dots.
MPKG_TAG_PATTERN='curl-[0-9]+_[0-9]+_[0-9]+'
MPKG_TARBALL_URL='https://github.com/curl/curl/releases/download/${tag}/${tag//_/.}.tar.gz'
MPKG_TARBALL='${tag//_/.}.tar.gz'
MPKG_SRCDIR='${tag//_/.}'
MPKG_DESTDIR='${tag//_/.}'

MPKG_CONFIGURE_FLAGS=(
    --with-openssl='${MPKG_PREFIX}'
    --without-libpsl
    --enable-shared
)

mpkg_describe() {
    # Pin the trust store instead of relying on configure's probe, which finds
    # nothing in a minimal container and silently produces a curl that cannot
    # verify any certificate.
    if [[ -n "${MPKG_CA_BUNDLE}" ]]; then
        MPKG_CONFIGURE_FLAGS+=(--with-ca-bundle="${MPKG_CA_BUNDLE}")
    elif [[ -n "${MPKG_CA_PATH}" ]]; then
        MPKG_CONFIGURE_FLAGS+=(--with-ca-path="${MPKG_CA_PATH}")
    else
        MPKG_CONFIGURE_FLAGS+=(--with-ca-fallback)
    fi
}

mpkg_discover() {
    mpkg_super discover || return 1
    MPKG_VERSION="${MPKG_VERSION//_/.}"
}

# A curl whose libcurl.so is missing is the failure that silently disabled
# git's https support, so check for it explicitly.
mpkg_verify() {
    if ! mpkg::have_shared_lib curl; then
        mpkg::err "libcurl.so is not linkable from ${MPKG_PREFIX}/lib"
        return 1
    fi
    if ! "${MPKG_PREFIX}/bin/curl" -fsS -o /dev/null https://curl.se/ 2>/dev/null; then
        mpkg::warn "the new curl could not complete an https request"
        mpkg::warn "check the CA bundle: ${MPKG_CA_BUNDLE:-<none found>}"
    else
        mpkg::step "https verified"
    fi
    return 0
}
