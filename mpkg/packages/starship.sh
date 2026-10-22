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

mpkg_post_install() {
    local cfg="${HOME}/.config/starship"
    mkdir -p "${cfg}" || return 1
    if [[ -f "${cfg}/jetpack.toml" ]]; then
        mpkg::step "preset already present"
        return 0
    fi
    mpkg::download "https://starship.rs/presets/toml/jetpack.toml" "${cfg}/jetpack.toml" \
        || mpkg::warn "could not download the jetpack preset"
    return 0
}
