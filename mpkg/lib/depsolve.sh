# mpkg / lib/depsolve.sh — dependency resolution.
#
# Depth-first post-order walk over MPKG_DEPENDS (plus MPKG_OPTDEPENDS when
# --with-optional is given), producing an install order in which every package
# appears after everything it needs. Cycles are reported with the full chain
# rather than blowing the stack.

declare -A MPKG_DEP_STATE=()     # unset | visiting | done
MPKG_ORDER=()

mpkg::_visit() {
    local name="$1" chain="$2" dep

    case "${MPKG_DEP_STATE[$name]:-}" in
        done)     return 0 ;;
        visiting) mpkg::err "dependency cycle: ${chain} -> ${name}"; return 1 ;;
    esac

    mpkg::exists "${name}" || { mpkg::err "unknown dependency '${name}'${chain:+ (required by ${chain##*-> })}"; return 1; }
    MPKG_DEP_STATE[$name]="visiting"

    mpkg::meta_load "${name}" || return 1
    for dep in ${MPKG_META_DEPS[$name]:-}; do
        mpkg::_visit "${dep}" "${chain:+${chain} -> }${name}" || return 1
    done
    if [[ ${MPKG_WITH_OPT:-0} -eq 1 ]]; then
        for dep in ${MPKG_META_OPTDEPS[$name]:-}; do
            mpkg::_visit "${dep}" "${chain:+${chain} -> }${name}" || return 1
        done
    fi

    MPKG_DEP_STATE[$name]="done"
    MPKG_ORDER+=("${name}")
}

# resolve <pkg...> -> fills MPKG_ORDER
mpkg::resolve() {
    local p
    MPKG_DEP_STATE=()
    MPKG_ORDER=()
    if [[ ${MPKG_NO_DEPS:-0} -eq 1 ]]; then
        for p in "$@"; do
            mpkg::exists "${p}" || { mpkg::err "no such package: ${p}"; return 1; }
            MPKG_ORDER+=("${p}")
        done
        return 0
    fi
    for p in "$@"; do
        mpkg::_visit "${p}" "" || return 1
    done
}

# Pretty-print the dependency tree of one package.
mpkg::dep_tree() {
    local name="$1" indent="${2:-}" last="${3:-1}" dep deps i n
    local marker="${indent}"
    if [[ -n "${indent}" || "${3:-}" != "" ]]; then
        marker="${indent}$([[ ${last} -eq 1 ]] && printf '`- ' || printf '|- ')"
    fi
    mpkg::exists "${name}" || { printf '%s%s (unknown)\n' "${marker}" "${name}"; return; }
    mpkg::meta_load "${name}" >/dev/null 2>&1

    local mark=" "
    mpkg::db_installed "${name}" && mark="*"
    printf '%s%s%s %s\n' "${marker}" "${name}" "$([[ ${mark} == '*' ]] && printf ' [installed]')" \
        "$([[ -n "${MPKG_META_DEPS[$name]:-}" ]] && printf '')"

    deps=(${MPKG_META_DEPS[$name]:-})
    n=${#deps[@]}
    local child_indent="${indent}"
    if [[ -n "${3:-}" ]]; then
        child_indent="${indent}$([[ ${last} -eq 1 ]] && printf '   ' || printf '|  ')"
    fi
    for (( i = 0; i < n; i++ )); do
        mpkg::dep_tree "${deps[$i]}" "${child_indent}" "$(( i == n - 1 ))" "child"
    done
}
