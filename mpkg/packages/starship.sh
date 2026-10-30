mpkg_inherit scriptcommon

MPKG_TITLE="Starship"
MPKG_DESC="Cross-shell prompt"
MPKG_HOMEPAGE="https://starship.rs/"
MPKG_PROBE_CMD="starship"
MPKG_DEPENDS=(curl)

MPKG_GUARD_CMD="starship"
MPKG_VERSION_CMD="starship --version"
MPKG_SCRIPT_URL="https://starship.rs/install.sh"
MPKG_SCRIPT_RUNNER=(sh)
MPKG_SCRIPT_ARGS=(--bin-dir '${MPKG_PREFIX}/bin' -y)

# The preset (https://starship.rs/presets/) the prompt uses; empty for
# starship's own default look.
MPKG_STARSHIP_PRESET="jetpack"
MPKG_STARSHIP_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/starship"

# After Oh My Zsh (10), so that the prompt is starship's, not the theme's.
MPKG_SHELL_ORDER=80

mpkg_post_install() {
    [[ -n "${MPKG_STARSHIP_PRESET}" ]] || return 0
    local file="${MPKG_STARSHIP_DIR}/${MPKG_STARSHIP_PRESET}.toml"
    mkdir -p "${MPKG_STARSHIP_DIR}" || return 1
    if [[ -f "${file}" ]]; then
        mpkg::step "preset ${MPKG_STARSHIP_PRESET} already present"
        return 0
    fi
    mpkg::download "https://starship.rs/presets/toml/${MPKG_STARSHIP_PRESET}.toml" "${file}" \
        || mpkg::warn "could not download the ${MPKG_STARSHIP_PRESET} preset"
    return 0
}

mpkg_shell_env() {
    [[ -n "${MPKG_STARSHIP_PRESET}" ]] || return 0
    printf '[ -f "%s" ] && export STARSHIP_CONFIG="%s"\n' \
        "${MPKG_STARSHIP_DIR}/${MPKG_STARSHIP_PRESET}.toml" "${MPKG_STARSHIP_DIR}/${MPKG_STARSHIP_PRESET}.toml"
}

mpkg_shell_rc() {
    cat <<'SH'
if command -v starship >/dev/null 2>&1; then
    if [ -n "${ZSH_VERSION:-}" ]; then eval "$(starship init zsh)"
    elif [ -n "${BASH_VERSION:-}" ]; then eval "$(starship init bash)"
    fi
fi
SH
}
