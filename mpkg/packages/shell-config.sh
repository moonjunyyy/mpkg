# Hooks mpkg into the startup files of every shell on the machine. It knows
# shells, not packages: what a package needs in the environment (JAVA_HOME,
# ~/go/bin, nvm, a prompt) is declared by that package and kept as a fragment
# under var/mpkg/shell/ (lib/shell.sh). Two files load them, both shipped with
# mpkg and linked into the prefix by the mpkg package:
#
#   share/mpkg/env.sh          the environment, POSIX sh; also what mpkg itself
#                              sources before building
#   share/mpkg/interactive.sh  prompts, plugins, shell functions, the upgrade
#                              notice: bash and zsh, interactive only
#
# This package writes a marked block into each startup file that applies:
#
#   ~/.profile        env          sh, dash, and bash when it has no ~/.bash_profile
#   ~/.bash_profile   env          only if it already exists (creating one would
#                                  make bash stop reading ~/.profile)
#   ~/.bashrc         env + interactive   interactive non-login bash
#   ~/.zprofile       env          zsh login shells (after macOS's path_helper)
#   ~/.zshrc          env + interactive   interactive zsh
#
# bash/zsh files are touched only when that shell is installed. Only mpkg's own
# block is ever replaced; the rest of each file is left alone. Installing it
# also rewrites every package's fragments from their current declarations.

mpkg_inherit pkgcommon

MPKG_TITLE="Shell configuration"
MPKG_DESC="Loads the environment installed packages declare, in sh, bash and zsh"
MPKG_KIND="config"
MPKG_UNVERSIONED=1
MPKG_PROBE_CMD="sh"
MPKG_DEPENDS=(mpkg)

MPKG_SHELL_FILES="${MPKG_PREFIX}/share/mpkg"
MPKG_MARK_BEGIN="# >>> mpkg >>>"
MPKG_MARK_END="# <<< mpkg <<<"

mpkg_run() {
    [[ -f "${MPKG_SHELL_FILES}/env.sh" && -f "${MPKG_SHELL_FILES}/interactive.sh" ]] \
        || { mpkg::err "${MPKG_SHELL_FILES}/env.sh is missing; run 'mpkg install --force mpkg'"; return 1; }
    mpkg::shell_sync || return 1
    local f kind
    while read -r f kind; do
        mpkg::shell_patch_rc "${f}" "${kind}" || return 1
    done < <(mpkg::shell_targets)
    MPKG_VERSION="present"
    MPKG_DEST_NAME=""
    MPKG_STATUS="installed"
}

# "<file> env|all" for every startup file this machine's shells read.
mpkg::shell_targets() {
    printf '%s env\n' "${HOME}/.profile"
    [[ -f "${HOME}/.bash_profile" ]] && printf '%s env\n' "${HOME}/.bash_profile"
    if command -v bash >/dev/null 2>&1; then
        printf '%s all\n' "${HOME}/.bashrc"
    fi
    if command -v zsh >/dev/null 2>&1; then
        printf '%s env\n' "${ZDOTDIR:-${HOME}}/.zprofile"
        printf '%s all\n' "${ZDOTDIR:-${HOME}}/.zshrc"
    fi
}

# Drop mpkg's block from <file>, leaving everything else as it was.
mpkg::shell_strip_block() {
    local rc="$1" tmp
    [[ -f "${rc}" ]] && grep -qF "${MPKG_MARK_BEGIN}" "${rc}" || return 0
    tmp="$(mktemp "${rc}.mpkg.XXXXXX")" || return 1
    awk -v b="${MPKG_MARK_BEGIN}" -v e="${MPKG_MARK_END}" \
        'index($0,b){s=1} !s{print} index($0,e){s=0}' "${rc}" > "${tmp}" \
        && cat "${tmp}" > "${rc}"      # cat, not mv: keep a symlinked rc a symlink
    rm -f "${tmp}"
}

# patch_rc <file> env|all
mpkg::shell_patch_rc() {
    local rc="$1" kind="$2"
    if [[ -f "${rc}" ]] && grep -qF "${MPKG_MARK_BEGIN}" "${rc}"; then
        mpkg::step "refreshing the mpkg block in ${rc}"
        mpkg::shell_strip_block "${rc}" || return 1
    else
        mpkg::step "adding an mpkg block to ${rc}"
        [[ -s "${rc}" ]] && cp "${rc}" "${rc}.mpkg-backup.$(date +%s)"
    fi
    # The marker must start a line of its own.
    [[ -s "${rc}" && -n "$(tail -c 1 "${rc}")" ]] && printf '\n' >> "${rc}"
    {
        printf '%s\n' "${MPKG_MARK_BEGIN}"
        mpkg::shell_block "${kind}"
        printf '%s\n' "${MPKG_MARK_END}"
    } >> "${rc}"
}

mpkg_link() { return 0; }

# Every file that may carry a block, whether or not that shell is still here.
# The fragments stay: they belong to their packages.
mpkg_remove() {
    local rc
    for rc in "${HOME}/.profile" "${HOME}/.bash_profile" "${HOME}/.bashrc" \
              "${ZDOTDIR:-${HOME}}/.zprofile" "${ZDOTDIR:-${HOME}}/.zshrc"; do
        mpkg::shell_strip_block "${rc}"
    done
}
