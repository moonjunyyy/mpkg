# packages/srccommon.sh — base class for packages built from a source tarball.
#
#   discover -> fetch -> prepare -> configure -> build -> install -> link -> cleanup
#
# A package overrides only what differs; `mpkg_super <stage>` runs the version
# below, so an override can extend instead of replace.

mpkg_inherit pkgcommon

MPKG_KIND="source"

mpkg_run() {
    mpkg_discover || return 1
    mpkg::report_versions
    if mpkg::is_current; then
        MPKG_STATUS="current"
        mpkg_cleanup
        return 0
    fi
    mpkg_fetch     || return 1
    mpkg_prepare   || return 1
    mpkg_configure || return 1
    mpkg_build     || return 1
    mpkg_install   || return 1
    mpkg_link      || return 1
    mpkg::drop_old_tree
    mpkg_cleanup
    MPKG_STATUS="installed"
}

mpkg_fetch() {
    MPKG_TARBALL_FILE="$(mpkg::render "${MPKG_TARBALL}")"
    MPKG_SRC_DIR="$(mpkg::render "${MPKG_SRCDIR}")"
    MPKG_DEST_NAME="$(mpkg::render "${MPKG_DESTDIR}")"
    MPKG_TMPFILES+=("${MPKG_TARBALL_FILE}" "${MPKG_SRC_DIR}" objdir)

    [[ -n "${MPKG_SRC_DIR}" && -n "${MPKG_TARBALL_FILE}" && -n "${MPKG_DEST_NAME}" ]] \
        || { mpkg::err "${MPKG_NAME}: version templates rendered empty"; return 1; }
    rm -rf -- "${MPKG_SRC_DIR}" objdir
    mpkg::download "$(mpkg::render "${MPKG_TARBALL_URL}")" "${MPKG_TARBALL_FILE}" || return 1

    mpkg::step "extracting ${MPKG_TARBALL_FILE}"
    mpkg::run tar -xf "${MPKG_TARBALL_FILE}" \
        || mpkg::stage_failed "${MPKG_NAME}: could not extract ${MPKG_TARBALL_FILE}"
}

mpkg_prepare() {
    # Leftovers of an interrupted build of this version: start from empty.
    if [[ -d "${MPKG_SOFT}/${MPKG_DEST_NAME}" ]] && ! mpkg::store_in_use "${MPKG_DEST_NAME}"; then
        rm -rf "${MPKG_SOFT:?}/${MPKG_DEST_NAME}"
    fi
    mkdir -p "${MPKG_SOFT}/${MPKG_DEST_NAME}" || return 1
    if [[ "${MPKG_INTREE}" -eq 1 ]]; then
        cd "${MPKG_SRC_DIR}" || return 1
    else
        mkdir -p objdir && cd objdir || return 1
    fi
}

mpkg_configure() {
    # Packages with no configure script (Lua) set MPKG_CONFIGURE="".
    [[ -z "${MPKG_CONFIGURE}" ]] && return 0

    local script
    if [[ "${MPKG_INTREE}" -eq 1 ]]; then
        script="./${MPKG_CONFIGURE}"
    else
        script="../${MPKG_SRC_DIR}/${MPKG_CONFIGURE}"
    fi
    [[ -x "${script}" ]] || { mpkg::err "no configure script at ${script}"; return 1; }

    local -a flags=()
    local f
    for f in "${MPKG_CONFIGURE_FLAGS[@]}"; do flags+=("$(mpkg::render "${f}")"); done

    mpkg::step "configuring"
    mpkg::run env "CFLAGS=${_CFLAGS}" "CXXFLAGS=${_CXXFLAGS}" "LDFLAGS=${_LDFLAGS}" \
        "${script}" --prefix="${MPKG_SOFT}/${MPKG_DEST_NAME}" "${flags[@]}" \
        || mpkg::stage_failed "${MPKG_NAME}: configure failed"
}

mpkg::render_make_vars() {
    MPKG_RENDERED_VARS=()
    local v
    for v in "${MPKG_MAKE_VARS[@]}"; do
        MPKG_RENDERED_VARS+=("$(mpkg::render "${v}")")
    done
}

mpkg_build() {
    local -a MPKG_RENDERED_VARS
    mpkg::render_make_vars
    mpkg::step "building with -j${_NPROCESSORS}"
    mpkg::run "${MPKG_MAKE:-make}" -j"${_NPROCESSORS}" "${MPKG_MAKE_TARGETS[@]}" "${MPKG_RENDERED_VARS[@]}" \
        || mpkg::stage_failed "${MPKG_NAME}: build failed"
}

mpkg_install() {
    local -a MPKG_RENDERED_VARS
    mpkg::render_make_vars
    mpkg::step "installing into ${MPKG_SOFT}/${MPKG_DEST_NAME}"
    mpkg::run "${MPKG_MAKE:-make}" "${MPKG_RENDERED_VARS[@]}" "${MPKG_INSTALL_TARGETS[@]}" \
        || mpkg::stage_failed "${MPKG_NAME}: make ${MPKG_INSTALL_TARGETS[*]} failed"
}
