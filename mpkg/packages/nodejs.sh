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

MPKG_ENV=('set NVM_DIR ${HOME}/.nvm')

# nvm itself is loaded by interactive shells only. Without a node on PATH
# every other process -- an editor started from a GUI, git hooks, `sh -c`,
# mpkg building mason -- would have none, and node-based tools (pyright,
# bash-language-server) fail with "env: node: No such file". So the newest
# installed node goes on PATH for all; nvm, where it is loaded, still
# switches to its default.
mpkg_shell_env() {
    cat <<'SH'
if ! command -v node >/dev/null 2>&1 && [ -d "${NVM_DIR}/versions/node" ]; then
    _mpkg_node="$(ls "${NVM_DIR}/versions/node" 2>/dev/null | sed -n 's/^v\([0-9.]*\)$/\1/p' \
                  | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)"
    [ -n "${_mpkg_node}" ] && mpkg_path PATH "${NVM_DIR}/versions/node/v${_mpkg_node}/bin"
    unset _mpkg_node
fi
SH
}

mpkg_shell_rc() {
    printf '%s\n' '[ -s "${NVM_DIR:-${HOME}/.nvm}/nvm.sh" ] && . "${NVM_DIR:-${HOME}/.nvm}/nvm.sh"'
}

mpkg_post_install() {
    export NVM_DIR="${HOME}/.nvm"
    # shellcheck source=/dev/null
    [[ -s "${NVM_DIR}/nvm.sh" ]] && . "${NVM_DIR}/nvm.sh" >/dev/null 2>&1
    command -v nvm >/dev/null 2>&1 || { mpkg::err "nvm did not install correctly"; return 1; }
    mpkg::step "installing the Node.js LTS release"
    mpkg::run nvm install --lts || return 1
    mpkg::run nvm use --lts     || return 1
    mpkg::run nvm alias default 'lts/*'
}

mpkg_remove() {
    mpkg::warn "leaving ${HOME}/.nvm in place; delete it by hand to remove nvm"
}
