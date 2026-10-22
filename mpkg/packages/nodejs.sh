mpkg_inherit scriptcommon

MPKG_TITLE="Node.js"
MPKG_DESC="Node.js LTS, installed through nvm"
MPKG_HOMEPAGE="https://nodejs.org/"
MPKG_PROBE_CMD="node"
MPKG_DEPENDS=(curl git)

# nvm itself is unversioned; what matters is whether a node has been installed.
MPKG_GUARD_DIR="${HOME}/.nvm/versions/node"
MPKG_VERSION_CMD="node --version"
MPKG_SCRIPT_URL="https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh"
MPKG_SCRIPT_ENV=(PROFILE=/dev/null)

mpkg_env() {
    export NVM_DIR="${HOME}/.nvm"
    # shellcheck source=/dev/null
    [[ -s "${NVM_DIR}/nvm.sh" ]] && . "${NVM_DIR}/nvm.sh" >/dev/null 2>&1
    return 0
}

mpkg_post_install() {
    mpkg_env
    command -v nvm >/dev/null 2>&1 || { mpkg::err "nvm did not install correctly"; return 1; }
    mpkg::step "installing the Node.js LTS release"
    mpkg::run nvm install --lts || return 1
    mpkg::run nvm use --lts     || return 1
    mpkg::run nvm alias default 'lts/*'
}

mpkg_remove() {
    mpkg::warn "leaving ${HOME}/.nvm in place; delete it by hand to remove nvm"
}
