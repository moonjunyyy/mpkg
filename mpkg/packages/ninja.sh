mpkg_inherit ghcommon

MPKG_TITLE="Ninja"
MPKG_DESC="Small, fast build system; the backend Meson drives"
MPKG_HOMEPAGE="https://ninja-build.org/"

MPKG_GITHUB_REPO="ninja-build/ninja"

# ninja-linux.zip is x86_64; every other platform carries its name.
mpkg_describe() {
    case "${_OS}/${_UARCH}" in
        linux/x86_64) MPKG_ASSET='ninja-linux.zip' ;;
        linux/*)      MPKG_ASSET='ninja-linux-${_UARCH}.zip' ;;
        macos/*)      MPKG_ASSET='ninja-mac.zip' ;;
    esac
}
