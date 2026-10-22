# mpkg / lib/registry.sh — discovering packages and reading their metadata.
#
# Metadata is read by sourcing the package class in a subshell, so querying a
# package can never disturb the one currently being installed.

declare -A MPKG_META_SEEN=()
declare -A MPKG_META_TITLE=() MPKG_META_KIND=() MPKG_META_DESC=()
declare -A MPKG_META_DEPS=()  MPKG_META_OPTDEPS=() MPKG_META_PROBE=()
declare -A MPKG_META_HOME=()  MPKG_META_REQS=()

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
        command -v "${c}" >/dev/null 2>&1 || missing+=("${c}")
    done
    (( ${#missing[@]} == 0 )) && return 0
    mpkg::err "${name} needs these system tools first: ${missing[*]}"
    return 1
}
