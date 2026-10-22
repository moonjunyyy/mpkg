# packages/mesoncommon.sh — base class for source tarballs built with Meson
# (GTK, girara, zathura).
#
#   discover -> fetch -> prepare -> configure -> build -> install -> link -> cleanup
#
# Only the build-system stages differ from srccommon. MPKG_CONFIGURE_FLAGS
# carries -Doption=value pairs. --libdir=lib is forced: on Debian-like systems
# Meson would otherwise pick lib/x86_64-linux-gnu, which is on none of the
# prefix's search paths.

mpkg_inherit srccommon

MPKG_KIND="meson"
MPKG_DEPENDS=(meson ninja)
MPKG_REQUIRES_CMD=(cc pkg-config)
MPKG_TARBALL='${tag}.tar.xz'

mpkg_configure() {
    local -a flags=()
    local f
    for f in "${MPKG_CONFIGURE_FLAGS[@]}"; do flags+=("$(mpkg::render "${f}")"); done

    # Meson reads CFLAGS/LDFLAGS once, at setup; the rpath in _LDFLAGS is what
    # lets the result find the prefix's libraries without LD_LIBRARY_PATH.
    mpkg::step "configuring with meson"
    mpkg::run env "CFLAGS=${_CFLAGS}" "CXXFLAGS=${_CXXFLAGS}" "LDFLAGS=${_LDFLAGS}" \
        meson setup . "../${MPKG_SRC_DIR}" \
            --prefix="${MPKG_SOFT}/${MPKG_DEST_NAME}" \
            --libdir=lib \
            --buildtype=release \
            "${flags[@]}" \
        || mpkg::stage_failed "${MPKG_NAME}: meson setup failed"
}

mpkg_build() {
    mpkg::step "building with -j${_NPROCESSORS}"
    mpkg::run meson compile -j "${_NPROCESSORS}" \
        || mpkg::stage_failed "${MPKG_NAME}: build failed"
}

mpkg_install() {
    mpkg::step "installing into ${MPKG_SOFT}/${MPKG_DEST_NAME}"
    mpkg::run meson install --no-rebuild \
        || mpkg::stage_failed "${MPKG_NAME}: meson install failed"
}
