mpkg_inherit gnucommon

MPKG_TITLE="ncurses"
MPKG_DESC="Terminal handling library and terminfo database, for tmux"
MPKG_PROBE_CMD=""
MPKG_REQUIRES_CMD=(cc make)

# Static libraries only. A shared libncursesw.so.6 / libtinfo.so.6 in
# ${MPKG_PREFIX}/lib would sit on LD_LIBRARY_PATH in front of the system copies
# and be picked up by the login shell and everything else linked against
# ncurses. Static, only the programs built here see it.
#
# Terminfo is looked up in the prefix first (the database this package links
# there), then in the usual system locations, so terminals the system knows
# about and this release does not still work.
MPKG_CONFIGURE_FLAGS=(
    --without-shared
    --with-normal
    --enable-widec
    --without-debug
    --without-ada
    --without-cxx-binding
    --without-manpages
    --without-tests
    --enable-pc-files
    '--with-pkg-config-libdir=${MPKG_SOFT}/${tag}/lib/pkgconfig'
    '--with-default-terminfo-dir=${MPKG_PREFIX}/share/terminfo'
    '--with-terminfo-dirs=${MPKG_PREFIX}/share/terminfo:/etc/terminfo:/lib/terminfo:/usr/share/terminfo:/usr/lib/terminfo'
)

# The static archives must still be position-independent, or linking them
# into anything shared (or a PIE, the default on most distros) fails.
mpkg_configure() {
    local _CFLAGS="${_CFLAGS} -fPIC"
    mpkg_super configure
}
