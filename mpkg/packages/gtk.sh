# GTK 4, the toolkit zathura is written against.
#
# The libraries under it (glib, cairo, pango, harfbuzz, gdk-pixbuf, graphene,
# epoxy, X11/Wayland) come from the system when pkg-config can see them; GTK
# ships Meson wraps for the rest and builds them as subprojects, installed in
# this same tree. Only the toolkit itself is wanted, so demos, tests, docs and
# introspection are off, and GStreamer is not pulled in for video playback.

mpkg_inherit gnomecommon

MPKG_TITLE="GTK"
MPKG_DESC="GTK 4 GUI toolkit"
MPKG_HOMEPAGE="https://www.gtk.org/"
MPKG_PROBE_CMD=""
MPKG_REQUIRES_CMD+=(c++)

MPKG_GNOME_MAJOR=4
MPKG_CONFIGURE_FLAGS=(
    -Dmedia-gstreamer=disabled
    -Dintrospection=disabled
    -Ddocumentation=false
    -Dman-pages=false
    -Dbuild-demos=false
    -Dbuild-examples=false
    -Dbuild-tests=false
    -Dbuild-testsuite=false
)

# GTK reads its settings through GSettings, and GLib only finds schemas that
# are compiled into ${datadir}/glib-2.0/schemas/gschemas.compiled on
# XDG_DATA_DIRS (shell-config adds ${MPKG_PREFIX}/share). A GTK program without
# them aborts the first time it opens a file chooser.
#
# That file is compiled from every schema in the prefix, so it belongs to the
# prefix, not to this tree. Meson compiles one into the tree too; linked, it
# would be overwritten by the prefix's own on post-install, and a later
# relink --force would put the tree's GTK-only copy back over it.
MPKG_GTK_SCHEMAS_CACHE="share/glib-2.0/schemas/gschemas.compiled"

mpkg_install() {
    mpkg_super install || return 1
    rm -f "${MPKG_SOFT}/${MPKG_DEST_NAME}/${MPKG_GTK_SCHEMAS_CACHE}"
}

mpkg_post_install() {
    local dir="${MPKG_PREFIX}/share/glib-2.0/schemas" files
    # Installs from before the tree's copy was dropped still list it.
    files="$(mpkg::db_files "${MPKG_NAME}")"
    if [[ -f "${files}" ]] && grep -qxF "${MPKG_GTK_SCHEMAS_CACHE}" "${files}"; then
        grep -vxF "${MPKG_GTK_SCHEMAS_CACHE}" "${files}" > "${files}.tmp" && mv -f "${files}.tmp" "${files}"
    fi
    [[ -d "${dir}" ]] || return 0
    command -v glib-compile-schemas >/dev/null 2>&1 \
        || { mpkg::warn "glib-compile-schemas not found; GSettings schemas left uncompiled"; return 0; }
    # A link left over from such an install: compile a real file, not through it.
    [[ -L "${dir}/gschemas.compiled" ]] && rm -f "${dir}/gschemas.compiled"
    mpkg::step "compiling GSettings schemas in ${dir}"
    mpkg::run glib-compile-schemas "${dir}" || mpkg::warn "glib-compile-schemas failed"
    return 0
}

mpkg_env() {
    # An unset XDG_DATA_DIRS means the spec's default, which must survive.
    [[ -n "${XDG_DATA_DIRS:-}" ]] || export XDG_DATA_DIRS="/usr/local/share:/usr/share"
    environment_prepend "XDG_DATA_DIRS" "${MPKG_PREFIX}/share"
    return 0
}

mpkg_verify() {
    local pc="${MPKG_SOFT}/${MPKG_DEST_NAME}/lib/pkgconfig"
    [[ "$(PKG_CONFIG_PATH="${pc}:${PKG_CONFIG_PATH:-}" pkg-config --modversion gtk4 2>/dev/null)" == "${MPKG_VERSION}" ]] \
        && return 0
    mpkg::err "gtk4.pc for ${MPKG_VERSION} is not in ${pc}"
    return 1
}
