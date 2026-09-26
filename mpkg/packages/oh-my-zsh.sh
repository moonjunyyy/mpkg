mpkg_inherit scriptcommon

MPKG_TITLE="Oh My Zsh"
MPKG_DESC="Zsh configuration framework, with autosuggestions and syntax highlighting"
MPKG_HOMEPAGE="https://ohmyz.sh/"
MPKG_PROBE_CMD="zsh"
MPKG_DEPENDS=(git)
MPKG_REQUIRES_CMD=(zsh)

MPKG_GUARD_DIR="${HOME}/.oh-my-zsh"
MPKG_SCRIPT_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
MPKG_SCRIPT_RUNNER=(zsh)
MPKG_SCRIPT_ARGS=(--unattended --keep-zshrc)
MPKG_SCRIPT_ENV=(RUNZSH=no CHSH=no)

MPKG_OMZ_PLUGINS=(
    "zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions"
    "zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting"
)

mpkg_post_install() {
    local custom="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}/plugins"
    local entry name url
    mkdir -p "${custom}" || return 1
    for entry in "${MPKG_OMZ_PLUGINS[@]}"; do
        read -r name url <<< "${entry}"
        if [[ -d "${custom}/${name}" ]]; then
            mpkg::step "plugin ${name} already present"
            continue
        fi
        mpkg::step "cloning plugin ${name}"
        mpkg::run git clone --depth=1 "${url}" "${custom}/${name}" \
            || mpkg::warn "could not clone ${name}"
    done
    return 0
}

mpkg_remove() {
    mpkg::warn "leaving ${HOME}/.oh-my-zsh in place; delete it by hand"
}
