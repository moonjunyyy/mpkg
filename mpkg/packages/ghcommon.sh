# packages/ghcommon.sh — base class for pre-built executables shipped inside a
# GitHub release archive (ripgrep, fd, fzf, bat, lazygit).
#
# A package names the repository, the asset and, when it is not the probe
# command, the executables to take:
#
#   MPKG_GITHUB_REPO="BurntSushi/ripgrep"
#   MPKG_ASSET='ripgrep-${version}-${_TRIPLE}.tar.gz'
#   MPKG_BINARIES=(rg)
#
# The executables are found wherever the archive keeps them and installed into
# bin/; any man pages that come along go to share/man/man1.

mpkg_inherit pkgcommon

MPKG_KIND="prebuilt"
MPKG_DESTDIR='${name}-${version}'
MPKG_ASSET_URL='https://github.com/${MPKG_GITHUB_REPO}/releases/download/${tag}/${asset}'

mpkg_run() {
    mpkg_discover || return 1
    mpkg::report_versions
    if mpkg::is_current; then
        MPKG_STATUS="current"
        mpkg_cleanup
        return 0
    fi
    mpkg_fetch   || return 1
    mpkg_install || return 1
    mpkg_link    || return 1
    mpkg::drop_old_tree
    mpkg_cleanup
    MPKG_STATUS="installed"
}

mpkg_fetch() {
    MPKG_ASSET_FILE="$(mpkg::render "${MPKG_ASSET}")"
    MPKG_DEST_NAME="$(mpkg::render "${MPKG_DESTDIR}")"
    MPKG_ASSET_STEM="${MPKG_NAME}-extract"
    MPKG_TMPFILES+=("${MPKG_ASSET_FILE}" "${MPKG_ASSET_STEM}")
    rm -rf "${MPKG_ASSET_STEM}"
    mpkg::download "$(mpkg::render "${MPKG_ASSET_URL}")" "${MPKG_ASSET_FILE}" || return 1

    mkdir -p "${MPKG_ASSET_STEM}" || return 1
    mpkg::step "extracting ${MPKG_ASSET_FILE}"
    case "${MPKG_ASSET_FILE}" in
        *.zip) mpkg::run unzip -q "${MPKG_ASSET_FILE}" -d "${MPKG_ASSET_STEM}" ;;
        *)     mpkg::run tar -xf "${MPKG_ASSET_FILE}" -C "${MPKG_ASSET_STEM}" ;;
    esac || mpkg::stage_failed "${MPKG_NAME}: could not extract ${MPKG_ASSET_FILE}"
}

mpkg_install() {
    local dest="${MPKG_SOFT}/${MPKG_DEST_NAME}" bin found man
    local -a bins=("${MPKG_BINARIES[@]}")
    (( ${#bins[@]} )) || bins=("${MPKG_PROBE_CMD}")

    rm -rf "${dest}"
    mkdir -p "${dest}/bin" || return 1
    for bin in "${bins[@]}"; do
        found="$(find "${MPKG_ASSET_STEM}" -type f -name "${bin}" | head -n1)"
        [[ -n "${found}" ]] \
            || { mpkg::err "${MPKG_NAME}: no '${bin}' inside ${MPKG_ASSET_FILE}"; return 1; }
        install -m 755 "${found}" "${dest}/bin/${bin}" || return 1
    done

    while IFS= read -r -d '' man; do
        mkdir -p "${dest}/share/man/man1"
        install -m 644 "${man}" "${dest}/share/man/man1/" || return 1
    done < <(find "${MPKG_ASSET_STEM}" -type f -name '*.1' -print0)

    mpkg::step "installed ${bins[*]} into ${dest}/bin"
}

# The binary must run on this machine; a wrong-architecture or wrong-libc asset
# otherwise only shows up the first time it is used.
mpkg_verify() {
    local bins=("${MPKG_BINARIES[@]}")
    (( ${#bins[@]} )) || bins=("${MPKG_PROBE_CMD}")
    if ! "${MPKG_SOFT}/${MPKG_DEST_NAME}/bin/${bins[0]}" --version >/dev/null 2>&1; then
        mpkg::err "${bins[0]} does not run on this machine (${_OS}/${_UARCH})"
        return 1
    fi
}
