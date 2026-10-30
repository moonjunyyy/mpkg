# mpkg / lib/registry.sh — discovering packages and reading their metadata.
#
# Metadata is read by sourcing the package class in a subshell, so querying a
# package can never disturb the one currently being installed.

declare -A MPKG_META_SEEN=()
declare -A MPKG_META_TITLE=() MPKG_META_KIND=() MPKG_META_DESC=()
declare -A MPKG_META_DEPS=()  MPKG_META_OPTDEPS=() MPKG_META_PROBE=()
declare -A MPKG_META_HOME=()  MPKG_META_REQS=() MPKG_META_PROVIDES=()

# Every installable package: packages/*.sh minus the *common.sh base classes.
mpkg::available() {
    local f n
    shopt -s nullglob
    for f in "${MPKG_PACKAGES}"/*.sh; do
        n="$(basename "${f}" .sh)"
        [[ "${n}" == *common ]] && continue
        printf '%s\n' "${n}"
    done | sort
    shopt -u nullglob
}

mpkg::exists() { [[ -r "${MPKG_PACKAGES}/$1.sh" && "$1" != *common ]]; }

mpkg::meta_load() {
    local name="$1" out rc key val
    [[ -n "${MPKG_META_SEEN[$name]:-}" ]] && return 0
    mpkg::exists "${name}" || { mpkg::err "no such package: ${name}"; return 1; }

    out="$(
        mpkg::class_load "${name}" >/dev/null || exit 1
        printf 'title\t%s\n'      "${MPKG_TITLE}"
        printf 'kind\t%s\n'       "${MPKG_KIND}"
        printf 'desc\t%s\n'       "${MPKG_DESC}"
        printf 'home\t%s\n'       "${MPKG_HOMEPAGE}"
        printf 'probe\t%s\n'      "${MPKG_PROBE_CMD}"
        printf 'deps\t%s\n'       "${MPKG_DEPENDS[*]:-}"
        printf 'optdeps\t%s\n'    "${MPKG_OPTDEPENDS[*]:-}"
        printf 'reqs\t%s\n'       "${MPKG_REQUIRES_CMD[*]:-}"
        printf 'provides\t%s\n'   "${MPKG_PROVIDES_CMD[*]:-}"
    )"
    rc=$?
    (( rc != 0 )) && { mpkg::err "cannot read metadata for '${name}'"; return 1; }

    while IFS=$'\t' read -r key val; do
        case "${key}" in
            title)   MPKG_META_TITLE[$name]="${val}" ;;
            kind)    MPKG_META_KIND[$name]="${val}" ;;
            desc)    MPKG_META_DESC[$name]="${val}" ;;
            home)    MPKG_META_HOME[$name]="${val}" ;;
            probe)   MPKG_META_PROBE[$name]="${val}" ;;
            deps)    MPKG_META_DEPS[$name]="${val}" ;;
            optdeps) MPKG_META_OPTDEPS[$name]="${val}" ;;
            reqs)    MPKG_META_REQS[$name]="${val}" ;;
            provides) MPKG_META_PROVIDES[$name]="${val}" ;;
        esac
    done <<< "${out}"
    MPKG_META_SEEN[$name]=1
}

mpkg::meta() {
    local name="$1" field="$2"
    mpkg::meta_load "${name}" || return 1
    case "${field}" in
        title)   printf '%s' "${MPKG_META_TITLE[$name]}" ;;
        kind)    printf '%s' "${MPKG_META_KIND[$name]}" ;;
        desc)    printf '%s' "${MPKG_META_DESC[$name]}" ;;
        home)    printf '%s' "${MPKG_META_HOME[$name]}" ;;
        probe)   printf '%s' "${MPKG_META_PROBE[$name]}" ;;
        deps)    printf '%s' "${MPKG_META_DEPS[$name]}" ;;
        optdeps) printf '%s' "${MPKG_META_OPTDEPS[$name]}" ;;
        reqs)    printf '%s' "${MPKG_META_REQS[$name]}" ;;
    esac
}

# Warn about missing system tools; returns 1 if any are absent.
mpkg::check_requires() {
    local name="$1" c missing=()
    for c in $(mpkg::meta "${name}" reqs); do
        mpkg::have_cmd "${c}" || missing+=("${c}")
    done
    (( ${#missing[@]} == 0 )) && return 0
    mpkg::err "${name} needs these system tools first: ${missing[*]}"
    for c in "${missing[@]}"; do mpkg::say "      ${c}: $(mpkg::system_hint "${c}")"; done
    return 1
}

# provider_of <cmd> — the package whose MPKG_PROVIDES_CMD names <cmd>, in
# MPKG_PROVIDER (empty when none). The index reads every package once, and
# only the first time a required command turns out to be missing.
declare -A MPKG_PROVIDER_OF=()
MPKG_PROVIDER_INDEXED=0
mpkg::provider_of() {
    local p c
    MPKG_PROVIDER=""
    if (( ! MPKG_PROVIDER_INDEXED )); then
        for p in $(mpkg::available); do
            mpkg::meta_load "${p}" 2>/dev/null || continue
            for c in ${MPKG_META_PROVIDES[$p]:-}; do
                [[ -n "${MPKG_PROVIDER_OF[$c]:-}" ]] || MPKG_PROVIDER_OF[$c]="${p}"
            done
        done
        MPKG_PROVIDER_INDEXED=1
    fi
    MPKG_PROVIDER="${MPKG_PROVIDER_OF[$1]:-}"
}

# req_providers <pkg> — in MPKG_REQ_PROVIDERS, the packages that provide the
# system tools <pkg> requires and this machine lacks.
mpkg::req_providers() {
    local c
    MPKG_REQ_PROVIDERS=()
    mpkg::meta_load "$1" || return 1
    for c in ${MPKG_META_REQS[$1]:-}; do
        mpkg::have_cmd "${c}" && continue
        mpkg::provider_of "${c}"
        [[ -n "${MPKG_PROVIDER}" && "${MPKG_PROVIDER}" != "$1" ]] \
            && MPKG_REQ_PROVIDERS+=("${MPKG_PROVIDER}")
    done
    return 0
}
