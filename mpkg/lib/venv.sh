# mpkg / lib/venv.sh — environments: named, independent views of the store.
#
# Every package is built once into $MPKG_SOFT/<name>-<version> (the store) and
# linked into the base prefix. An environment is a second symlink farm over the
# same store:
#
#   $MPKG_ENVS/<env>/
#       bin/ lib/ include/ share/ ...  links into $MPKG_SOFT/<tree>/...
#       activate                       sourceable from bash, zsh or sh
#       .mpkg/config                   isolated=0|1
#       .mpkg/pkgs/<pkg>               name / version / dest of the linked tree
#       .mpkg/pkgs/<pkg>.files         manifest of the links it owns
#
# An environment pins the tree it linked. Upgrading or removing a package in
# the base keeps any tree an environment still uses; the tree is deleted when
# the last user lets go of it (mpkg::store_release).
#
# Builds always go through the base prefix -- configure scripts need the
# dependencies' headers and libraries there -- so an environment is a view,
# not a separate build root. An *isolated* environment hides the base prefix
# from PATH and the compiler/library search paths once activated.

mpkg::venv_dir()     { printf '%s/%s' "${MPKG_ENVS}" "$1"; }
mpkg::venv_meta()    { printf '%s/%s/.mpkg' "${MPKG_ENVS}" "$1"; }
mpkg::venv_rec()     { printf '%s/%s/.mpkg/pkgs/%s' "${MPKG_ENVS}" "$1" "$2"; }
mpkg::venv_exists()  { [[ -n "$1" && -d "$(mpkg::venv_meta "$1")" ]]; }

mpkg::venv_check_name() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && return 0
    mpkg::err "invalid environment name '$1' (letters, digits, . _ -)"
    return 1
}

mpkg::venv_need() {
    mpkg::venv_exists "$1" && return 0
    mpkg::err "no environment named '$1' (see: mpkg venv list)"
    return 1
}

mpkg::venv_names() {
    local d
    shopt -s nullglob
    for d in "${MPKG_ENVS}"/*/.mpkg; do
        d="${d%/.mpkg}"
        printf '%s\n' "${d##*/}"
    done
    shopt -u nullglob
}

mpkg::venv_pkgs() {
    local r
    shopt -s nullglob
    for r in "$(mpkg::venv_meta "$1")"/pkgs/*; do
        [[ "${r}" == *.files ]] && continue
        printf '%s\n' "${r##*/}"
    done
    shopt -u nullglob
}

mpkg::venv_get() {
    local rec; rec="$(mpkg::venv_rec "$1" "$2")"
    [[ -f "${rec}" ]] || return 1
    sed -n "s/^$3=//p" "${rec}" | head -n1
}

mpkg::venv_isolated() {
    grep -qx 'isolated=1' "$(mpkg::venv_meta "$1")/config" 2>/dev/null
}

# --- the store --------------------------------------------------------------

# Environments that link <tree>.
# (Lists are read into arrays before looping: leaving a `while read` over a
# process substitution early makes the producer die of SIGPIPE, noisily.)
mpkg::venv_refs() {
    local tree="$1" e p
    local -a envs pkgs
    [[ -n "${tree}" ]] || return 0
    mapfile -t envs < <(mpkg::venv_names)
    for e in "${envs[@]}"; do
        mapfile -t pkgs < <(mpkg::venv_pkgs "${e}")
        for p in "${pkgs[@]}"; do
            if [[ "$(mpkg::venv_get "${e}" "${p}" dest)" == "${tree}" ]]; then
                printf '%s\n' "${e}"
                break
            fi
        done
    done
}

# Is <tree> still wanted by the base database or by any environment?
mpkg::store_in_use() {
    local tree="$1" p
    local -a pkgs
    mapfile -t pkgs < <(mpkg::db_list)
    for p in "${pkgs[@]}"; do
        [[ "$(mpkg::db_dest "${p}")" == "${tree}" ]] && return 0
    done
    [[ -n "$(mpkg::venv_refs "${tree}")" ]]
}

# Delete <tree> from the store once nothing uses it any more.
mpkg::store_release() {
    local tree="$1"
    [[ -n "${tree}" && "${tree}" != */* && -d "${MPKG_SOFT}/${tree}" ]] || return 0
    mpkg::store_in_use "${tree}" && return 0
    rm -rf "${MPKG_SOFT:?}/${tree}"
    mpkg::step "deleted ${tree} from the store (no longer used)"
}

# The store tree holding <pkg> at <version>: the base install, or a tree some
# environment still pins. Empty when that version is not in the store.
mpkg::store_find() {
    local pkg="$1" version="$2" e
    if mpkg::db_installed "${pkg}" && [[ -z "${version}" || "$(mpkg::db_version "${pkg}")" == "${version}" ]]; then
        mpkg::db_dest "${pkg}"
        return 0
    fi
    [[ -n "${version}" ]] || return 1
    local -a envs
    mapfile -t envs < <(mpkg::venv_names)
    for e in "${envs[@]}"; do
        if [[ "$(mpkg::venv_get "${e}" "${pkg}" version)" == "${version}" ]]; then
            mpkg::venv_get "${e}" "${pkg}" dest
            return 0
        fi
    done
    return 1
}

# Every version of <pkg> present in the store, for error messages.
mpkg::store_versions() {
    local pkg="$1" e v
    { mpkg::db_installed "${pkg}" && mpkg::db_version "${pkg}"
      while IFS= read -r e; do
          v="$(mpkg::venv_get "${e}" "${pkg}" version)" && printf '%s\n' "${v}"
      done < <(mpkg::venv_names)
    } | mpkg::vsort -u | tr '\n' ' '
}

# --- linking ----------------------------------------------------------------

mpkg::venv_link_pkg() {
    local env="$1" pkg="$2" tree="$3" version="$4"
    local dir; dir="$(mpkg::venv_dir "${env}")"
    local rec; rec="$(mpkg::venv_rec "${env}" "${pkg}")"
    local old; old="$(mpkg::venv_get "${env}" "${pkg}" dest 2>/dev/null)"

    [[ -d "${MPKG_SOFT}/${tree}" ]] || { mpkg::err "${pkg}: ${MPKG_SOFT}/${tree} is missing"; return 1; }
    [[ -n "${old}" ]] && mpkg::unlink_manifest "${dir}" "${rec}.files"
    mpkg::link_tree "${MPKG_SOFT}/${tree}" "${dir}" "${rec}.files" || return 1
    printf 'name=%s\nversion=%s\ndest=%s\ndate=%s\n' "${pkg}" "${version}" "${tree}" \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${rec}"
    [[ -n "${old}" && "${old}" != "${tree}" ]] && mpkg::store_release "${old}"
    return 0
}

mpkg::venv_unlink_pkg() {
    local env="$1" pkg="$2"
    local dir; dir="$(mpkg::venv_dir "${env}")"
    local rec; rec="$(mpkg::venv_rec "${env}" "${pkg}")"
    local tree; tree="$(mpkg::venv_get "${env}" "${pkg}" dest)" || return 0
    mpkg::unlink_manifest "${dir}" "${rec}.files"
    rm -f "${rec}"
    find "${dir}" -mindepth 1 -path "${dir}/.mpkg" -prune -o -type d -empty -print 2>/dev/null \
        | sort -r | while IFS= read -r d; do rmdir "${d}" 2>/dev/null; done
    mpkg::store_release "${tree}"
}

# --- activation -------------------------------------------------------------

# Written as POSIX sh (no ${!var}, no arrays) so bash, zsh and dash can all
# source it. Saves the variables it touches and restores them on deactivate.
mpkg::venv_write_activate() {
    local env="$1" dir; dir="$(mpkg::venv_dir "${env}")"
    local iso=0
    mpkg::venv_isolated "${env}" && iso=1
    {
        printf '# Generated by mpkg for the environment "%s". Do not edit.\n' "${env}"
        printf '#   activate:    . %s/activate      (or: mpkg_activate %s)\n' "${dir}" "${env}"
        printf '#   deactivate:  mpkg_deactivate\n\n'
        printf '_mpkg_env_name=%s\n'    "'${env//\'/}'"
        printf '_mpkg_env_dir=%s\n'     "'${dir//\'/}'"
        printf '_mpkg_env_base=%s\n'    "'${MPKG_PREFIX//\'/}'"
        printf '_mpkg_env_isolated=%s\n\n' "${iso}"
        cat <<'ACTIVATE'
mpkg_deactivate() {
    for _mpkg_v in PATH LD_LIBRARY_PATH LIBRARY_PATH CPATH PKG_CONFIG_PATH MANPATH PS1; do
        eval "_mpkg_saved=\${_MPKG_OLD_${_mpkg_v}+set}"
        [ "${_mpkg_saved}" = set ] || continue
        eval "_mpkg_o=\${_MPKG_OLD_${_mpkg_v}}"
        if [ "${_mpkg_o}" = __mpkg_unset__ ]; then unset "${_mpkg_v}"
        else eval "${_mpkg_v}=\${_mpkg_o}"; [ "${_mpkg_v}" = PS1 ] || export "${_mpkg_v}"
        fi
        unset "_MPKG_OLD_${_mpkg_v}"
    done
    unset MPKG_VENV MPKG_VENV_DIR _mpkg_v _mpkg_o _mpkg_saved
    hash -r 2>/dev/null
    unset -f mpkg_deactivate
}

# Switching environments: leave the current one first.
if [ -n "${MPKG_VENV:-}" ] && command -v mpkg_deactivate >/dev/null 2>&1; then
    mpkg_deactivate
    # mpkg_deactivate removed itself; this file defines it again below.
    . "${_mpkg_env_dir}/activate"
    return 0 2>/dev/null
fi

for _mpkg_v in PATH LD_LIBRARY_PATH LIBRARY_PATH CPATH PKG_CONFIG_PATH MANPATH PS1; do
    eval "_mpkg_o=\${${_mpkg_v}-__mpkg_unset__}"
    eval "_MPKG_OLD_${_mpkg_v}=\${_mpkg_o}"
done

# Remove one directory from a colon-separated variable.
_mpkg_strip() {
    eval "_mpkg_s=\":\${$1-}:\""
    while :; do
        case "${_mpkg_s}" in
            *":$2:"*) _mpkg_s="${_mpkg_s%%:"$2":*}:${_mpkg_s#*:"$2":}" ;;
            *) break ;;
        esac
    done
    _mpkg_s="${_mpkg_s#:}"; _mpkg_s="${_mpkg_s%:}"
    eval "export $1=\"\${_mpkg_s}\""
}

# Put a directory in front of a colon-separated variable -- only one the
# environment has: a variable is not touched for what is not installed.
_mpkg_front() {
    [ -d "$2" ] || return 0
    _mpkg_strip "$1" "$2"
    eval "_mpkg_s=\${$1-}"
    if [ -n "${_mpkg_s}" ]; then eval "export $1=\"\$2:\${_mpkg_s}\""
    else eval "export $1=\"\$2\""
    fi
}

if [ "${_mpkg_env_isolated}" = 1 ]; then
    for _mpkg_d in bin; do _mpkg_strip PATH "${_mpkg_env_base}/${_mpkg_d}"; done
    for _mpkg_d in lib lib64; do
        _mpkg_strip LD_LIBRARY_PATH "${_mpkg_env_base}/${_mpkg_d}"
        _mpkg_strip LIBRARY_PATH    "${_mpkg_env_base}/${_mpkg_d}"
        _mpkg_strip PKG_CONFIG_PATH "${_mpkg_env_base}/${_mpkg_d}/pkgconfig"
    done
    _mpkg_strip CPATH   "${_mpkg_env_base}/include"
    _mpkg_strip MANPATH "${_mpkg_env_base}/share/man"
fi

_mpkg_front PATH            "${_mpkg_env_dir}/bin"
# dyld ignores LD_LIBRARY_PATH; macOS binaries find libraries by rpath.
if [ "$(uname -s)" != Darwin ]; then
    _mpkg_front LD_LIBRARY_PATH "${_mpkg_env_dir}/lib64"
    _mpkg_front LD_LIBRARY_PATH "${_mpkg_env_dir}/lib"
fi
_mpkg_front LIBRARY_PATH    "${_mpkg_env_dir}/lib64"
_mpkg_front LIBRARY_PATH    "${_mpkg_env_dir}/lib"
_mpkg_front CPATH           "${_mpkg_env_dir}/include"
_mpkg_front PKG_CONFIG_PATH "${_mpkg_env_dir}/lib64/pkgconfig"
_mpkg_front PKG_CONFIG_PATH "${_mpkg_env_dir}/lib/pkgconfig"
# A trailing ':' keeps man's built-in search path after ours.
if [ -d "${_mpkg_env_dir}/share/man" ]; then
    MANPATH="${_mpkg_env_dir}/share/man:${MANPATH-}"; export MANPATH
fi

export MPKG_VENV="${_mpkg_env_name}" MPKG_VENV_DIR="${_mpkg_env_dir}"
if [ -z "${MPKG_VENV_NO_PROMPT:-}" ] && [ -n "${PS1-}" ]; then
    PS1="(${_mpkg_env_name}) ${PS1}"
fi
unset -f _mpkg_strip _mpkg_front
unset _mpkg_v _mpkg_o _mpkg_d _mpkg_s
hash -r 2>/dev/null
ACTIVATE
    } > "${dir}/activate"
}

# --- commands ---------------------------------------------------------------

mpkg::venv_create() {
    local env="$1"; shift
    mpkg::venv_check_name "${env}" || return 1
    if mpkg::venv_exists "${env}"; then
        mpkg::say "environment '${env}' already exists"
    else
        mkdir -p "$(mpkg::venv_meta "${env}")/pkgs" "$(mpkg::venv_dir "${env}")/bin" || return 1
        printf 'isolated=%s\ncreated=%s\n' "${MPKG_ISOLATED:-0}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            > "$(mpkg::venv_meta "${env}")/config"
        mpkg::venv_write_activate "${env}"
        mpkg::ok "created $( (( ${MPKG_ISOLATED:-0} )) && printf 'isolated ')environment '${env}' in $(mpkg::venv_dir "${env}")"
    fi
    (( $# )) && { mpkg::venv_add "${env}" "$@" || return 1; }
    mpkg::say "activate with:  . $(mpkg::venv_dir "${env}")/activate"
}

# add <env> <pkg>[@version]... — with dependencies unless --no-deps.
# Packages not yet in the base are installed first. A version other than the
# base one has to be in the store already (pinned by another environment).
mpkg::venv_add() {
    local env="$1"; shift
    mpkg::venv_need "${env}" || return 1
    (( $# )) || { mpkg::err "venv add: name at least one package"; return 1; }

    local spec pkg ver tree p
    local -a names=() missing=()
    declare -A want_ver=()
    for spec in "$@"; do
        pkg="${spec%%@*}"
        ver=""; [[ "${spec}" == *@* ]] && ver="${spec#*@}"
        mpkg::exists "${pkg}" || { mpkg::err "no such package: ${pkg}"; return 1; }
        names+=("${pkg}")
        want_ver[$pkg]="${ver}"
        [[ -z "${ver}" ]] && ! mpkg::db_installed "${pkg}" && missing+=("${pkg}")
    done

    if (( ${#missing[@]} )); then
        mpkg::say "Not installed yet: ${missing[*]}"
        mpkg::install "${missing[@]}" || return 1
        mpkg::say ""
    fi

    mpkg::resolve "${names[@]}" || return 1
    local -a skipped=()
    mpkg::head "environment ${env}"
    for p in "${MPKG_ORDER[@]}"; do
        ver="${want_ver[$p]:-}"
        if ! tree="$(mpkg::store_find "${p}" "${ver}")"; then
            if [[ -n "${ver}" ]]; then
                mpkg::err "${p} ${ver} is not in the store (have: $(mpkg::store_versions "${p}"))"
                return 1
            fi
            # A dependency that is not installed: install it into the base.
            mpkg::install "${p}" >/dev/null || { mpkg::err "could not install ${p}"; return 1; }
            tree="$(mpkg::store_find "${p}" "")" || return 1
        fi
        # Meta, config and installer-script packages have no tree to link.
        if [[ -z "${tree}" ]]; then
            [[ " ${names[*]} " == *" ${p} "* ]] && skipped+=("${p}")
            continue
        fi
        [[ -z "${ver}" ]] && ver="$(mpkg::db_version "${p}")"
        if [[ "$(mpkg::venv_get "${env}" "${p}" dest 2>/dev/null)" == "${tree}" && ${MPKG_FORCE:-0} -eq 0 ]]; then
            mpkg::ok "${p} ${ver} already linked"
            continue
        fi
        mpkg::say "  ${p} ${ver}"
        mpkg::venv_link_pkg "${env}" "${p}" "${tree}" "${ver}" || return 1
    done
    (( ${#skipped[@]} )) && mpkg::warn "not linkable (managed outside the store): ${skipped[*]}"
    hash -r 2>/dev/null
    return 0
}

mpkg::venv_remove() {
    local env="$1" p; shift
    mpkg::venv_need "${env}" || return 1
    for p in "$@"; do
        if [[ ! -f "$(mpkg::venv_rec "${env}" "${p}")" ]]; then
            mpkg::warn "${p} is not in '${env}'"
            continue
        fi
        mpkg::head "removing ${p} from ${env}"
        mpkg::venv_unlink_pkg "${env}" "${p}"
    done
}

# update <env> [pkg...] — repoint pinned packages at the base's current version.
mpkg::venv_update() {
    local env="$1" p tree cur; shift
    mpkg::venv_need "${env}" || return 1
    local -a pkgs=("$@")
    (( ${#pkgs[@]} )) || mapfile -t pkgs < <(mpkg::venv_pkgs "${env}")
    mpkg::head "updating ${env}"
    for p in "${pkgs[@]}"; do
        cur="$(mpkg::venv_get "${env}" "${p}" version)" || { mpkg::warn "${p} is not in '${env}'"; continue; }
        if ! mpkg::db_installed "${p}"; then
            mpkg::warn "${p}: not installed in the base; keeping ${cur}"
            continue
        fi
        tree="$(mpkg::db_dest "${p}")"
        if [[ "$(mpkg::venv_get "${env}" "${p}" dest)" == "${tree}" ]]; then
            mpkg::ok "${p} ${cur} is current"
            continue
        fi
        mpkg::say "  ${p} ${cur} -> $(mpkg::db_version "${p}")"
        mpkg::venv_link_pkg "${env}" "${p}" "${tree}" "$(mpkg::db_version "${p}")" || return 1
    done
    mpkg::venv_write_activate "${env}"
}

mpkg::venv_delete() {
    local env="$1" p
    mpkg::venv_need "${env}" || return 1
    [[ "${MPKG_VENV:-}" == "${env}" ]] && mpkg::warn "'${env}' is active in this shell; run mpkg_deactivate"
    mpkg::head "deleting environment ${env}"
    local -a trees=()
    while IFS= read -r p; do
        trees+=("$(mpkg::venv_get "${env}" "${p}" dest)")
    done < <(mpkg::venv_pkgs "${env}")
    rm -rf "$(mpkg::venv_dir "${env}")"
    for p in "${trees[@]}"; do mpkg::store_release "${p}"; done
    mpkg::ok "deleted ${env}"
}

mpkg::venv_list() {
    local env="$1" e n p v base flag
    if [[ -z "${env}" ]]; then
        n=0
        while IFS= read -r e; do
            flag=""; mpkg::venv_isolated "${e}" && flag="isolated"
            [[ "${MPKG_VENV:-}" == "${e}" ]] && flag="${flag:+${flag}, }active"
            printf '%-16s %3d package(s)  %s\n' "${e}" "$(mpkg::venv_pkgs "${e}" | wc -l)" "${flag}"
            n=$(( n + 1 ))
        done < <(mpkg::venv_names)
        (( n == 0 )) && mpkg::say "no environments (create one: mpkg venv create <name> [pkg...])"
        return 0
    fi
    mpkg::venv_need "${env}" || return 1
    while IFS= read -r p; do
        v="$(mpkg::venv_get "${env}" "${p}" version)"
        base="$(mpkg::db_version "${p}" 2>/dev/null)"
        if [[ -z "${base}" ]]; then flag="(not in base)"
        elif [[ "${base}" != "${v}" ]]; then flag="(pinned; base has ${base})"
        else flag=""
        fi
        printf '%-16s %-18s %s\n' "${p}" "${v}" "${flag}"
    done < <(mpkg::venv_pkgs "${env}")
}

# Store trees neither the base nor any environment uses: failed or
# interrupted builds, trees that predate the database.
mpkg::store_gc() {
    local d tree n=0
    local -a orphans=()
    shopt -s nullglob
    for d in "${MPKG_SOFT}"/*/; do
        tree="$(basename "${d}")"
        mpkg::store_in_use "${tree}" || orphans+=("${tree}")
    done
    shopt -u nullglob
    (( ${#orphans[@]} )) || { mpkg::say "store is clean"; return 0; }
    mpkg::say "Unused trees in ${MPKG_SOFT}:"
    for tree in "${orphans[@]}"; do
        printf '  %-32s %s\n' "${tree}" "$(du -sh "${MPKG_SOFT}/${tree}" 2>/dev/null | cut -f1)"
    done
    [[ ${MPKG_DRY_RUN:-0} -eq 1 ]] && return 0
    mpkg::say "(a tree that predates the database can be kept with 'mpkg adopt' instead)"
    mpkg::confirm "delete them?" || return 0
    for tree in "${orphans[@]}"; do
        rm -rf "${MPKG_SOFT:?}/${tree}" && n=$(( n + 1 ))
    done
    mpkg::ok "deleted ${n} tree(s)"
}
