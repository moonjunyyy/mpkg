mpkg_inherit srccommon

MPKG_TITLE="Lua"
MPKG_DESC="Lua interpreter and library"
MPKG_HOMEPAGE="https://www.lua.org/"
MPKG_PROBE_CMD="lua"
MPKG_REQUIRES_CMD=(cc make)

MPKG_LISTING_URL="https://www.lua.org/ftp/"
MPKG_TAG_PATTERN='lua-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz'
MPKG_TARBALL_URL='https://www.lua.org/ftp/${tag}.tar.gz'
MPKG_INTREE=1

# Lua has no configure script; the platform is a make target instead, and the
# install prefix is a make variable rendered once the version is known.
MPKG_CONFIGURE=""
MPKG_MAKE_VARS=(
    MYCFLAGS=-fPIC
    'INSTALL_TOP=${MPKG_SOFT}/${tag}'
)

mpkg_describe() {
    # Lua's own platform targets; `posix` is the portable fallback.
    case "${_OS}" in
        macos)                  MPKG_MAKE_TARGETS=(macosx) ;;
        linux)                  MPKG_MAKE_TARGETS=(linux) ;;
        freebsd)                MPKG_MAKE_TARGETS=(freebsd) ;;
        openbsd|netbsd|dragonfly) MPKG_MAKE_TARGETS=(bsd) ;;
        sunos)                  MPKG_MAKE_TARGETS=(solaris) ;;
        *)                      MPKG_MAKE_TARGETS=(posix) ;;
    esac
    # MYCFLAGS/MYLDFLAGS, not CFLAGS/LDFLAGS: overriding CFLAGS from the
    # command line would drop Lua's own SYSCFLAGS (-DLUA_USE_LINUX, ...).
    MPKG_MAKE_VARS=('MYCFLAGS=${_CFLAGS} -fPIC' 'MYLDFLAGS=${_LDFLAGS}'
                    'INSTALL_TOP=${MPKG_SOFT}/${tag}')
}

# Without LUA_USE_LINUX / LUA_USE_MACOSX, Lua falls back to plain C89: no
# io.popen, no dlopen. It still runs, so the breakage only shows up later --
# luarocks refuses to start ("does not support io.popen") and C modules fail
# to load.
mpkg_verify() {
    local bin="${MPKG_SOFT}/${MPKG_DEST_NAME}/bin/lua"
    if ! "${bin}" -e 'io.popen("true"):close()' >/dev/null 2>&1; then
        mpkg::err "lua was built without POSIX support (io.popen unavailable)"
        mpkg::err "luarocks cannot run on it; check the platform make target."
        return 1
    fi
    mpkg::step "io.popen available"
}
