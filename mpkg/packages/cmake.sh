mpkg_inherit tarcommon

MPKG_TITLE="CMake"
MPKG_DESC="Cross-platform build system generator"
MPKG_HOMEPAGE="https://cmake.org/"
MPKG_GITHUB_REPO="Kitware/CMake"
MPKG_DESTDIR='cmake-${version}'

mpkg_discover() {
    mpkg_super discover || return 1
    if [[ "${_OS}" == "macos" ]]; then
        MPKG_ASSET_STEM="cmake-${MPKG_VERSION}-macos-universal"
    else
        MPKG_ASSET_STEM="cmake-${MPKG_VERSION}-linux-${_UARCH}"
    fi
    MPKG_ASSET_FILE="${MPKG_ASSET_STEM}.tar.gz"
    MPKG_ASSET_URL="https://github.com/${MPKG_GITHUB_REPO}/releases/download/${MPKG_TAG}/${MPKG_ASSET_FILE}"
}

# The archive keeps doc/ and man/ at its top level, next to bin/ and share/;
# linked as they are they would land in ${MPKG_PREFIX}/doc and ${MPKG_PREFIX}/man.
# On macOS the whole tree is inside CMake.app/Contents, and cmake-gui needs
# the bundle intact, so the bundle goes to libexec/ and bin/ points into it.
mpkg_install() {
    local dest="${MPKG_SOFT}/${MPKG_DEST_NAME}" root b
    [[ -d "${MPKG_ASSET_STEM}" ]] || { mpkg::err "archive did not contain ${MPKG_ASSET_STEM}/"; return 1; }
    rm -rf "${dest}"
    mkdir -p "${dest}/bin" "${dest}/share" || return 1

    if [[ "${_OS}" == "macos" ]]; then
        mkdir -p "${dest}/libexec" || return 1
        cp -a "${MPKG_ASSET_STEM}/CMake.app" "${dest}/libexec/" || return 1
        root="${dest}/libexec/CMake.app/Contents"
        for b in "${root}"/bin/*; do
            ln -s "../libexec/CMake.app/Contents/bin/${b##*/}" "${dest}/bin/${b##*/}" || return 1
        done
    else
        root="${MPKG_ASSET_STEM}"
        cp -a "${root}/bin/." "${dest}/bin/" || return 1
        cp -a "${root}/share/." "${dest}/share/" || return 1
        [[ -d "${root}/doc" ]] && { cp -a "${root}/doc" "${dest}/share/doc" || return 1; }
    fi
    [[ -d "${root}/man" ]] && { cp -a "${root}/man" "${dest}/share/man" || return 1; }
    mpkg::step "installed into ${dest}"
}

mpkg_verify() {
    "${MPKG_SOFT}/${MPKG_DEST_NAME}/bin/cmake" --version >/dev/null 2>&1 && return 0
    mpkg::err "the new cmake does not run"
    return 1
}
