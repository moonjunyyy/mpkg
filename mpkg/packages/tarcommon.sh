# packages/tarcommon.sh — base class for a pre-built tarball that already has
# a bin/ lib/ share/ layout inside (Neovim's release archives).
#
# The discover stage must set MPKG_VERSION, MPKG_ASSET_URL, MPKG_ASSET_FILE and
# MPKG_ASSET_STEM (the archive's single top-level directory).

mpkg_inherit pkgcommon

MPKG_KIND="prebuilt"

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
    MPKG_DEST_NAME="$(mpkg::render "${MPKG_DESTDIR}")"
    MPKG_TMPFILES+=("${MPKG_ASSET_FILE}" "${MPKG_ASSET_STEM}")
    rm -rf "${MPKG_ASSET_STEM}"
    mpkg::download "${MPKG_ASSET_URL}" "${MPKG_ASSET_FILE}" || return 1
    mpkg::step "extracting ${MPKG_ASSET_FILE}"
    mpkg::run tar -xf "${MPKG_ASSET_FILE}" \
        || mpkg::stage_failed "${MPKG_NAME}: could not extract ${MPKG_ASSET_FILE}"
}

mpkg_install() {
    local dest="${MPKG_SOFT}/${MPKG_DEST_NAME}"
    [[ -d "${MPKG_ASSET_STEM}" ]] || { mpkg::err "archive did not contain ${MPKG_ASSET_STEM}/"; return 1; }
    rm -rf "${dest}"
    mkdir -p "${dest}" || return 1
    # cp -a, not mv: the archive may contain symlinks that must stay relative.
    cp -a "${MPKG_ASSET_STEM}"/. "${dest}/" || return 1
    mpkg::step "installed into ${dest}"
}
