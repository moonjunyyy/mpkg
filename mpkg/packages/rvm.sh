mpkg_inherit scriptcommon

MPKG_TITLE="RVM"
MPKG_DESC="Ruby Version Manager, for switching between several Rubies"
MPKG_HOMEPAGE="https://rvm.io/"
MPKG_PROBE_CMD="rvm"
MPKG_DEPENDS=(curl git)
MPKG_REQUIRES_CMD=(bash)

MPKG_GUARD_DIR="${HOME}/.rvm"
MPKG_VERSION_CMD="${HOME}/.rvm/bin/rvm --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'"
MPKG_SCRIPT_URL="https://get.rvm.io"
# --ignore-dotfiles: the env file written by shell-config loads rvm; the
# installer must not append its own lines to ~/.bashrc, ~/.zshrc and friends.
# --autolibs=read-fail: when a Ruby build needs system libraries, report them
# and stop instead of trying to install them with sudo (there is no root here).
MPKG_SCRIPT_ARGS=(stable --ignore-dotfiles --autolibs=read-fail)

# The installer checks its own GPG signature whenever gpg is on PATH, and fails
# if the RVM maintainers' keys are not in the keyring yet.
mpkg_install() {
    local gpg key
    gpg="$(command -v gpg2 || command -v gpg)"
    if [[ -n "${gpg}" ]]; then
        mpkg::step "importing the RVM signing keys"
        for key in mpapis pkuczynski; do
            MPKG_TMPFILES+=("rvm-${key}.asc")
            mpkg::download "https://rvm.io/${key}.asc" "rvm-${key}.asc" \
                && mpkg::run "${gpg}" --batch --import "rvm-${key}.asc" \
                || mpkg::warn "could not import the ${key} key; the installer may refuse to run"
        done
    fi
    mpkg_super install
}

mpkg_env() {
    environment_prepend "PATH" "${HOME}/.rvm/bin"
    return 0
}

mpkg_verify() {
    [[ -x "${HOME}/.rvm/bin/rvm" ]] && return 0
    mpkg::err "rvm did not install into ${HOME}/.rvm"
    return 1
}

mpkg_remove() {
    mpkg::warn "run 'rvm implode' to remove ${HOME}/.rvm and every Ruby it built"
}
