mpkg_inherit gnucommon

MPKG_TITLE="GNU Make"
MPKG_DESC="Build automation tool; bootstraps from cc alone where there is no make"
MPKG_PROVIDES_CMD=(make)
MPKG_REQUIRES_CMD=(cc)

# With no GNU make to build it, the build.sh that configure puts in the build
# directory compiles ./make with cc alone (the route GNU make's README gives),
# and that make installs itself. With one, the usual make && make install.
mpkg::make_bootstrap() {
    ! "${MPKG_MAKE:-make}" --version 2>/dev/null | grep -q 'GNU Make'
}

mpkg_build() {
    mpkg::make_bootstrap || { mpkg_super build; return; }
    mpkg::step "no GNU make here: bootstrapping with build.sh"
    mpkg::run sh ./build.sh || mpkg::stage_failed "make: build.sh failed"
}

mpkg_install() {
    mpkg::make_bootstrap || { mpkg_super install; return; }
    mpkg::step "installing into ${MPKG_SOFT}/${MPKG_DEST_NAME} with the make just built"
    mpkg::run ./make install || mpkg::stage_failed "make: ./make install failed"
}

mpkg_verify() {
    "${MPKG_SOFT}/${MPKG_DEST_NAME}/bin/make" --version 2>/dev/null | grep -q 'GNU Make' && return 0
    mpkg::err "the new make does not run"
    return 1
}
