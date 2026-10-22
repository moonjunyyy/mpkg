# zathura itself reads no document format; each one is a plugin
# (zathura-pdf-poppler). Plugins are separate packages with their own trees,
# so the plugin directory compiled into zathura is the prefix's lib/zathura,
# where their links land, rather than the default inside zathura's own tree.

mpkg_inherit pwmtcommon

MPKG_TITLE="zathura"
MPKG_DESC="Keyboard-driven document viewer (install zathura-pdf-poppler for PDF)"
MPKG_PROBE_CMD="zathura"
MPKG_DEPENDS+=(girara gtk)

# Sphinx-built man pages, the rsvg icon conversion and the xvfb/weston test
# runners are all optional and rarely present.
MPKG_CONFIGURE_FLAGS=(
    -Dmanpages=disabled
    -Dconvert-icon=disabled
    -Dtests-x11=disabled
    -Dtests-wayland=disabled
)

# The shell completions go wherever the system's bash-completion and fish
# .pc files say, i.e. /usr/share; they are sent to zathura's own datadir
# instead, like the zsh one already is.
mpkg_prepare() {
    local build="${MPKG_SRC_DIR}/meson.build" data="${MPKG_SRC_DIR}/data/meson.build"
    grep -q "^plugindir = " "${build}" \
        || { mpkg::err "zathura: no plugindir assignment in ${build} to redirect"; return 1; }
    sed -i.orig "s|^plugindir = .*|plugindir = '${MPKG_PREFIX}/lib/zathura'|" "${build}" || return 1
    sed -i.orig -e 's/if bash_comp\.found()/if false/' -e 's/if fish_comp\.found()/if false/' "${data}" \
        || return 1
    mkdir -p "${MPKG_PREFIX}/lib/zathura"
    mpkg_super prepare
}

mpkg_verify() {
    "${MPKG_SOFT}/${MPKG_DEST_NAME}/bin/zathura" --version >/dev/null 2>&1 && return 0
    mpkg::err "the new zathura does not start"
    return 1
}
