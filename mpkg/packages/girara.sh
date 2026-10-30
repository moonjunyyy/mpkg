mpkg_inherit pwmtcommon

MPKG_TITLE="girara"
MPKG_DESC="Settings, shortcuts and command-line library behind zathura"
# girara needs GLib 2.84 or newer. Where the system's is older or absent,
# GLib comes from GTK's Meson subprojects, installed with gtk -- so gtk first.
MPKG_DEPENDS+=(gtk)
MPKG_CONFIGURE_FLAGS=(-Ddocs=disabled)

mpkg_verify() {
    mpkg::have_shared_lib girara && return 0
    mpkg::err "libgirara.so is not linkable from ${MPKG_PREFIX}/lib"
    return 1
}
