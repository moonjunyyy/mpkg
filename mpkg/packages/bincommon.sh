# packages/bincommon.sh — base class for a single pre-built executable
# published as a release asset (jq and friends).

mpkg_inherit pkgcommon

MPKG_KIND="binary"

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
    MPKG_TMPFILES+=("${MPKG_ASSET_FILE}")
    mpkg::download "$(mpkg::render "${MPKG_ASSET_URL}")" "${MPKG_ASSET_FILE}"
}

mpkg_install() {
    local bindir="${MPKG_SOFT}/${MPKG_DEST_NAME}/bin"
    mkdir -p "${bindir}" || return 1
    chmod +x "${MPKG_ASSET_FILE}" || return 1
    mv -f "${MPKG_ASSET_FILE}" "${bindir}/${MPKG_PROBE_CMD}" || return 1
    mpkg::step "installed ${bindir}/${MPKG_PROBE_CMD}"
}
