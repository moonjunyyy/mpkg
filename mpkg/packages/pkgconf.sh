mpkg_inherit srccommon

MPKG_TITLE="pkgconf"
MPKG_DESC="pkg-config, for machines that have none (macOS without Homebrew, minimal Linux)"
MPKG_HOMEPAGE="https://github.com/pkgconf/pkgconf"
MPKG_PROBE_CMD="pkgconf"
MPKG_PROVIDES_CMD=(pkg-config pkgconf)
MPKG_REQUIRES_CMD=(cc make)

# .tar.gz, not .tar.xz: GNU tar needs an xz binary for the latter.
MPKG_LISTING_URL="https://distfiles.ariadne.space/pkgconf/"
MPKG_TAG_PATTERN='pkgconf-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz'
MPKG_TARBALL_URL='https://distfiles.ariadne.space/pkgconf/${tag}.tar.gz'

# Its default search path would be its own tree. The prefix's .pc files come
# through PKG_CONFIG_PATH (env.sh); the built-in path is the system's, which
# differs by OS and, on Debian-like systems, by architecture. The system
# directories are what it strips from --cflags / --libs output.
mpkg_describe() {
    local -a pc sys
    local d dirs=""
    case "${_OS}" in
        macos)
            pc=(/opt/homebrew/lib/pkgconfig /opt/homebrew/share/pkgconfig
                /usr/local/lib/pkgconfig /usr/local/share/pkgconfig /usr/lib/pkgconfig)
            sys=(/usr/lib) ;;
        *)
            pc=(/usr/local/lib/pkgconfig /usr/local/share/pkgconfig
                "/usr/lib/${_UARCH}-linux-gnu/pkgconfig" /usr/lib64/pkgconfig
                /usr/lib/pkgconfig /usr/share/pkgconfig)
            sys=(/lib /lib64 /usr/lib /usr/lib64 "/lib/${_UARCH}-linux-gnu" "/usr/lib/${_UARCH}-linux-gnu") ;;
    esac
    for d in "${pc[@]}"; do [[ -d "${d}" ]] && dirs="${dirs:+${dirs}:}${d}"; done
    MPKG_CONFIGURE_FLAGS=(
        --disable-shared
        --with-pkg-config-dir="${dirs:-/usr/lib/pkgconfig}"
        --with-system-libdir="$(IFS=:; printf '%s' "${sys[*]}")"
        --with-system-includedir=/usr/include
    )
}

# Packages and build systems ask for pkg-config by that name.
mpkg_install() {
    mpkg_super install || return 1
    ln -sf pkgconf "${MPKG_SOFT}/${MPKG_DEST_NAME}/bin/pkg-config"
}

mpkg_verify() {
    "${MPKG_SOFT}/${MPKG_DEST_NAME}/bin/pkg-config" --version >/dev/null 2>&1 && return 0
    mpkg::err "the new pkg-config does not run"
    return 1
}
