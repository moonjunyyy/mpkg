# packages/scriptcommon.sh — base class for upstream installer scripts
# (rustup, nvm, uv, oh-my-zsh, starship).
#
# These manage their own layout outside $MPKG_SOFT, so there is nothing to link
# and no version to compare. A guard -- a command on PATH or a directory --
# decides whether there is anything to do.

mpkg_inherit pkgcommon

MPKG_KIND="script"
MPKG_UNVERSIONED=1

mpkg_run() {
    if [[ ${MPKG_FORCE:-0} -eq 0 ]] && mpkg::script_present; then
        MPKG_INSTALLED_VERSION="$(mpkg::script_version)"
        MPKG_STATUS="current"
        return 0
    fi
    mpkg_fetch   || return 1
    mpkg_install || return 1
    mpkg_cleanup
    MPKG_VERSION="$(mpkg::script_version)"
    MPKG_DEST_NAME=""
    MPKG_STATUS="installed"
}

mpkg::script_present() {
    [[ -n "${MPKG_GUARD_CMD}" ]] && command -v "${MPKG_GUARD_CMD}" >/dev/null 2>&1 && return 0
    [[ -n "${MPKG_GUARD_DIR}" && -d "${MPKG_GUARD_DIR}" ]] && return 0
    return 1
}

mpkg::script_version() {
    local out
    if [[ -n "${MPKG_VERSION_CMD}" ]]; then
        out="$(eval "${MPKG_VERSION_CMD}" 2>/dev/null | head -n1)"
    elif [[ -n "${MPKG_GUARD_CMD}" ]]; then
        out="$(mpkg::probe_version "${MPKG_GUARD_CMD}")"
    fi
    printf '%s' "${out:-present}"
}

mpkg_fetch() {
    [[ -n "${MPKG_SCRIPT_URL}" ]] || { mpkg::err "${MPKG_NAME}: no MPKG_SCRIPT_URL"; return 1; }
    MPKG_TMPFILES+=("${MPKG_SCRIPT_FILE}")
    mpkg::download "${MPKG_SCRIPT_URL}" "${MPKG_SCRIPT_FILE}"
}

mpkg_install() {
    local -a runner=()
    local a
    for a in "${MPKG_SCRIPT_RUNNER[@]}"; do runner+=("$(mpkg::render "${a}")"); done
    local -a args=()
    for a in "${MPKG_SCRIPT_ARGS[@]}"; do args+=("$(mpkg::render "${a}")"); done
    local -a envs=()
    for a in "${MPKG_SCRIPT_ENV[@]}"; do envs+=("$(mpkg::render "${a}")"); done

    command -v "${runner[0]}" >/dev/null 2>&1 \
        || { mpkg::err "${MPKG_NAME}: installer needs '${runner[0]}' on PATH"; return 1; }

    mpkg::step "running upstream installer"
    if (( ${#envs[@]} )); then
        mpkg::run env "${envs[@]}" "${runner[@]}" "${MPKG_SCRIPT_FILE}" "${args[@]}"
    else
        mpkg::run "${runner[@]}" "${MPKG_SCRIPT_FILE}" "${args[@]}"
    fi || mpkg::stage_failed "${MPKG_NAME}: upstream installer failed"
}

# Nothing of ours is linked into the prefix.
mpkg_link() { return 0; }
