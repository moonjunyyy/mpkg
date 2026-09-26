mpkg_inherit srccommon

MPKG_TITLE="libevent"
MPKG_DESC="Event notification library, for tmux"
MPKG_HOMEPAGE="https://libevent.org/"
MPKG_PROBE_CMD=""
MPKG_REQUIRES_CMD=(cc make)

# Tags look like release-2.1.13-stable; the version is 2.1.13.
MPKG_GITHUB_REPO="libevent/libevent"
MPKG_TARBALL_URL='https://github.com/${MPKG_GITHUB_REPO}/releases/download/${tag}/libevent-${version}-stable.tar.gz'
MPKG_TARBALL='libevent-${version}-stable.tar.gz'
MPKG_SRCDIR='libevent-${version}-stable'
MPKG_DESTDIR='libevent-${version}'
# tmux needs none of the TLS glue, and libevent 2.1 predates OpenSSL 4.
MPKG_CONFIGURE_FLAGS=(--disable-openssl --disable-mbedtls --disable-samples --disable-libevent-regress)

mpkg_verify() {
    mpkg::have_shared_lib event && return 0
    mpkg::err "libevent.so is not linkable from ${MPKG_PREFIX}/lib"
    return 1
}
