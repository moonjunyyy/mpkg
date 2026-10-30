mpkg_inherit srccommon

MPKG_TITLE="zlib"
MPKG_DESC="Compression library, for where the system has no zlib headers"
MPKG_HOMEPAGE="https://zlib.net/"
MPKG_PROBE_CMD=""
MPKG_REQUIRES_CMD=(cc make)

MPKG_GITHUB_REPO="madler/zlib"
MPKG_TARBALL_URL='https://github.com/${MPKG_GITHUB_REPO}/releases/download/${tag}/zlib-${version}.tar.gz'
MPKG_TARBALL='zlib-${version}.tar.gz'
MPKG_SRCDIR='zlib-${version}'
MPKG_DESTDIR='zlib-${version}'

# Static, like ncurses: a libz.so in the prefix would sit on LD_LIBRARY_PATH in
# front of the system's and be loaded by everything else. -fPIC lets libz.a go
# into shared objects (libcurl, Ruby's zlib extension). zlib's configure is its
# own, not autoconf: it takes --prefix and --static and reads CFLAGS from the
# environment, replacing its default -O3.
MPKG_CONFIGURE_FLAGS=(--static)

mpkg_configure() {
    local _CFLAGS="${_CFLAGS:+${_CFLAGS} }-O2 -fPIC"
    mpkg_super configure
}

mpkg_verify() {
    local dest="${MPKG_SOFT}/${MPKG_DEST_NAME}"
    [[ -f "${dest}/lib/libz.a" && -f "${dest}/include/zlib.h" ]] && return 0
    mpkg::err "libz.a or zlib.h is missing from ${dest}"
    return 1
}
