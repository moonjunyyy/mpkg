mpkg_inherit srccommon

MPKG_TITLE="tmux"
MPKG_DESC="Terminal multiplexer"
MPKG_HOMEPAGE="https://github.com/tmux/tmux"
# bison provides the yacc that configure insists on, even for release tarballs.
MPKG_DEPENDS=(libevent ncurses bison)
MPKG_REQUIRES_CMD=(cc make pkg-config)

# Tags are the bare version (3.7c), and so is the tarball's directory.
MPKG_GITHUB_REPO="tmux/tmux"
MPKG_TARBALL_URL='https://github.com/${MPKG_GITHUB_REPO}/releases/download/${tag}/tmux-${tag}.tar.gz'
MPKG_TARBALL='tmux-${tag}.tar.gz'
MPKG_SRCDIR='tmux-${tag}'
MPKG_DESTDIR='tmux-${version}'

# tmux's configure asks pkg-config for "tinfo" before anything else, so on a
# machine with the system ncurses headers it would build against those and
# ignore our ncurses. Its LIBTINFO_* override variables settle it.
mpkg_configure() {
    local pc="${MPKG_PREFIX}/lib/pkgconfig/ncursesw.pc"
    if [[ -f "${pc}" ]]; then
        local -x LIBTINFO_CFLAGS LIBTINFO_LIBS
        LIBTINFO_CFLAGS="$(pkg-config --cflags ncursesw)"
        LIBTINFO_LIBS="$(pkg-config --static --libs ncursesw)"
    fi
    mpkg_super configure
}

mpkg_verify() {
    "${MPKG_SOFT}/${MPKG_DEST_NAME}/bin/tmux" -V >/dev/null 2>&1 && return 0
    mpkg::err "the new tmux does not start"
    return 1
}
