# packages/cmakecommon.sh — base class for source tarballs built with CMake
# (poppler).
#
#   discover -> fetch -> prepare -> configure -> build -> install -> link -> cleanup
#
# MPKG_CONFIGURE_FLAGS carries -DVAR=value pairs. The install rpath points at
# the prefix, so the result finds its dependencies without LD_LIBRARY_PATH.
#
# CMake runs with the compiler's include-path variables unset. With
# /usr/include on CPATH, CMake stops treating it as implicit and passes a found
# library's `-isystem /usr/include` through; that puts /usr/include ahead of
# libstdc++'s headers and every `#include <cstdlib>` fails on its
# `#include_next <stdlib.h>`. The prefix's headers still come in via CFLAGS.
mpkg::cmake() {
    mpkg::run env -u CPATH -u CXXPATH -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH \
        "CFLAGS=${_CFLAGS}" "CXXFLAGS=${_CXXFLAGS}" "LDFLAGS=${_LDFLAGS}" cmake "$@"
}

mpkg_inherit srccommon

MPKG_KIND="cmake"
MPKG_DEPENDS=(cmake)
MPKG_REQUIRES_CMD=(cc c++ make)
MPKG_TARBALL='${tag}.tar.xz'

mpkg_configure() {
    local -a flags=()
    local f
    for f in "${MPKG_CONFIGURE_FLAGS[@]}"; do flags+=("$(mpkg::render "${f}")"); done

    mpkg::step "configuring with cmake"
    mpkg::cmake "../${MPKG_SRC_DIR}" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX="${MPKG_SOFT}/${MPKG_DEST_NAME}" \
            -DCMAKE_INSTALL_LIBDIR=lib \
            -DCMAKE_PREFIX_PATH="${MPKG_PREFIX}" \
            -DCMAKE_INSTALL_RPATH="${MPKG_PREFIX}/lib;${MPKG_SOFT}/${MPKG_DEST_NAME}/lib" \
            "${flags[@]}" \
        || mpkg::stage_failed "${MPKG_NAME}: cmake configure failed"
}

mpkg_build() {
    mpkg::step "building with -j${_NPROCESSORS}"
    mpkg::cmake --build . -j "${_NPROCESSORS}" \
        || mpkg::stage_failed "${MPKG_NAME}: build failed"
}

mpkg_install() {
    mpkg::step "installing into ${MPKG_SOFT}/${MPKG_DEST_NAME}"
    mpkg::cmake --install . \
        || mpkg::stage_failed "${MPKG_NAME}: cmake --install failed"
}
