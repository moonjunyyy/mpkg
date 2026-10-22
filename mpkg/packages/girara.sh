mpkg_inherit pwmtcommon

MPKG_TITLE="girara"
MPKG_DESC="Settings, shortcuts and command-line library behind zathura"
MPKG_CONFIGURE_FLAGS=(-Ddocs=disabled)

mpkg_verify() {
    mpkg::have_shared_lib girara && return 0
    mpkg::err "libgirara.so is not linkable from ${MPKG_PREFIX}/lib"
    return 1
}
