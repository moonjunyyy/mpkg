# packages/configcommon.sh — base class for configuration kept in this
# repository and installed into the user's home. A configuration is data:
# config/<name>/ (a directory, or a single file) in the checkout, copied to
# MPKG_CONFIG_DEST. A new one is a directory under config/ plus a package of
# a few lines:
#
#   mpkg_inherit configcommon
#   MPKG_TITLE="Neovim configuration"
#   MPKG_DEPENDS=(neovim)
#   MPKG_CONFIG_KEEP=(lazy-lock.json)
#
# mpkg owns what it installs and nothing else. It records a digest of the
# copy it installed (in $MPKG_STATE/config/<pkg>); a target that does not
# match -- written by hand, edited in place, or older than mpkg -- is moved to
# <target>.mpkg-backup.<time> before the new copy goes in, and 'mpkg remove'
# leaves it where it is.
#
# The version is a digest of the source, read from the checkout
# (mpkg::source_root): `mpkg update` reports a configuration that changed
# there, and `mpkg upgrade` installs it.

mpkg_inherit pkgcommon

MPKG_KIND="config"
MPKG_PROBE_CMD=""
# Templates; ${name} is the package. <x>-config installs config/<x> into
# ~/.config/<x> unless a package says otherwise.
MPKG_CONFIG_SRC='config/${name%-config}'
MPKG_CONFIG_DEST='${XDG_CONFIG_HOME:-${HOME}/.config}/${name%-config}'
# Paths inside the target that the program itself rewrites (lockfiles);
# a change to them is not an edit.
MPKG_CONFIG_KEEP=()

mpkg_run() {
    mpkg_discover || return 1
    mpkg::report_versions
    if [[ ${MPKG_FORCE:-0} -eq 0 && "${MPKG_VERSION}" == "${MPKG_INSTALLED_VERSION}" ]] \
       && mpkg::config_is_ours; then
        mpkg::config_adopt_legacy
        MPKG_STATUS="current"
        return 0
    fi
    mpkg_install || return 1
    MPKG_DEST_NAME=""
    MPKG_STATUS="installed"
}

mpkg::config_paths() {
    MPKG_CONFIG_FROM="$(mpkg::source_root)/$(mpkg::render "${MPKG_CONFIG_SRC}")"
    MPKG_CONFIG_TO="$(mpkg::render "${MPKG_CONFIG_DEST}")"
}

mpkg_discover() {
    mpkg::config_paths
    [[ -e "${MPKG_CONFIG_FROM}" ]] || { mpkg::err "${MPKG_NAME}: ${MPKG_CONFIG_FROM} is missing"; return 1; }
    MPKG_VERSION="$(mpkg::path_digest "${MPKG_CONFIG_FROM}")"
    MPKG_TAG="${MPKG_VERSION}"
}

# --- ownership --------------------------------------------------------------

mpkg::config_record() { printf '%s/config/%s' "${MPKG_STATE}" "${MPKG_NAME}"; }

# The target's digest, leaving out MPKG_CONFIG_KEEP and any extra names given.
mpkg::config_digest() {
    MPKG_DIGEST_SKIP="$* ${MPKG_CONFIG_KEEP[*]}" mpkg::path_digest "${MPKG_CONFIG_TO}"
}

# Is the target exactly what mpkg installed there?
mpkg::config_is_ours() {
    local rec; rec="$(mpkg::config_record)"
    [[ -e "${MPKG_CONFIG_TO}" ]] || return 1
    if [[ -f "${rec}" ]]; then
        [[ "$(sed -n 's/^target=//p' "${rec}")" == "${MPKG_CONFIG_TO}" ]] || return 1
        [[ "$(mpkg::config_digest)" == "$(sed -n 's/^digest=//p' "${rec}")" ]]
        return
    fi
    # Installed before ownership was recorded here: the digest was kept in the
    # target itself, as .mpkg-stamp.
    [[ -f "${MPKG_CONFIG_TO}/.mpkg-stamp" ]] \
        && [[ "$(mpkg::config_digest .mpkg-stamp)" == "$(cat "${MPKG_CONFIG_TO}/.mpkg-stamp")" ]]
}

mpkg::config_remember() {
    mkdir -p "${MPKG_STATE}/config" || return 1
    printf 'target=%s\ndigest=%s\n' "${MPKG_CONFIG_TO}" "$(mpkg::config_digest)" \
        > "$(mpkg::config_record)"
}

# Move a legacy in-target stamp into the record.
mpkg::config_adopt_legacy() {
    [[ -f "$(mpkg::config_record)" || ! -f "${MPKG_CONFIG_TO}/.mpkg-stamp" ]] && return 0
    rm -f "${MPKG_CONFIG_TO}/.mpkg-stamp"
    mpkg::config_remember
}

# --- stages -----------------------------------------------------------------

mpkg_install() {
    local to="${MPKG_CONFIG_TO}" backup
    if [[ -e "${to}" || -L "${to}" ]]; then
        if mpkg::config_is_ours; then
            rm -rf "${to:?}"
        else
            backup="${to}.mpkg-backup.$(date +%Y%m%d-%H%M%S)"
            mv "${to}" "${backup}" || return 1
            mpkg::warn "moved the existing ${to} to ${backup}"
        fi
    fi
    mpkg::step "installing ${to}"
    mkdir -p "$(dirname "${to}")" || return 1
    mpkg::copy_clean "${MPKG_CONFIG_FROM}" "${to}" || return 1
    mpkg::config_remember
}

mpkg_link() { return 0; }

mpkg_remove() {
    mpkg::config_paths
    if mpkg::config_is_ours; then
        rm -rf "${MPKG_CONFIG_TO:?}"
        mpkg::step "deleted ${MPKG_CONFIG_TO}"
    elif [[ -e "${MPKG_CONFIG_TO}" ]]; then
        mpkg::warn "${MPKG_CONFIG_TO} was changed since mpkg installed it; left in place"
    fi
    rm -f "$(mpkg::config_record)"
}
