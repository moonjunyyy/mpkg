# mpkg / lib/update.sh — asking upstream whether anything installed is behind.
#
# `mpkg update` runs only the discover stage of each installed package, which
# is what `mpkg upgrade` would do first, and installs nothing. What it finds is
# cached in $MPKG_STATE/updates, one "<pkg> <installed> <available>" line per
# package that is behind, so that the shell can announce upgrades at start-up
# without touching the network (shell/interactive.sh):
#
#   mpkg: 2 upgrade(s) available: git neovim  (mpkg upgrade)
#
# The same snippet starts `mpkg update --auto` in the background when the last
# check is older than MPKG_UPDATE_INTERVAL minutes (default a day). --auto is
# silent, and does nothing when a check is recent or one is already running.
#
# Packages run by their own installers (rustup, nvm, uv, ...), meta packages
# and unversioned ones have no version mpkg can compare, and are skipped.
# Configuration packages are checked against the checkout (configcommon).

MPKG_UPDATE_JOBS=8

mpkg::updates_file()  { printf '%s/updates' "${MPKG_STATE}"; }
mpkg::updates_stamp() { printf '%s/updates.checked' "${MPKG_STATE}"; }

# Cached lines still true: the package is installed at the version the check
# saw. An upgrade since then makes its line stale without anyone editing it.
mpkg::updates_pending() {
    local f p have avail
    f="$(mpkg::updates_file)"
    [[ -f "${f}" ]] || return 0
    while read -r p have avail; do
        [[ -n "${avail}" ]] || continue
        [[ "$(mpkg::db_version "${p}" 2>/dev/null)" == "${have}" ]] || continue
        printf '%s %s %s\n' "${p}" "${have}" "${avail}"
    done < "${f}"
}

# The version upstream offers for <pkg>, or nothing. Exit status 3: the
# package has no comparable version; anything else non-zero: the check failed.
# Runs in a subshell of its own so the class it loads goes with it, and in a
# private directory: an install may be using the work directory meanwhile.
mpkg::update_probe() {
    local name="$1" dir="$2"
    (
        MPKG_QUIET=1 MPKG_VERBOSE=0
        mkdir -p "${dir}" && cd "${dir}" || exit 1
        MPKG_WORK="${dir}" MPKG_LOG="${dir}/log"
        mpkg::class_load "${name}" >/dev/null 2>&1 || exit 1
        (( MPKG_UNVERSIONED )) && exit 3
        case "${MPKG_KIND}" in script|meta|config) exit 3 ;; esac
        mpkg_discover >>"${MPKG_LOG}" 2>&1 || exit 2
        [[ -n "${MPKG_VERSION}" ]] || exit 2
        printf '%s\n' "${MPKG_VERSION}"
    )
}

mpkg::update_check() {
    local auto="${1:-0}"; shift
    local -a pkgs=("$@")
    local stamp; stamp="$(mpkg::updates_stamp)"
    local interval="${MPKG_UPDATE_INTERVAL:-1440}"

    if (( auto )); then
        [[ -n "${MPKG_NO_UPDATE_CHECK:-}" ]] && return 0
        [[ "${interval}" =~ ^[0-9]+$ ]] || interval=1440
        [[ -f "${stamp}" && -z "$(find "${stamp}" -mmin +"${interval}" 2>/dev/null)" ]] && return 0
    fi

    # One check at a time; mkdir is atomic. A check older than an hour died.
    local lock="${MPKG_STATE}/updates.lock"
    if ! mkdir "${lock}" 2>/dev/null; then
        if [[ -n "$(find "${lock}" -maxdepth 0 -mmin +60 2>/dev/null)" ]]; then
            rm -rf "${lock}" && mkdir "${lock}" 2>/dev/null || return 0
        else
            (( auto )) && return 0
            mpkg::err "another update check is running (${lock})"
            return 1
        fi
    fi
    # Stamped up front, so shells started meanwhile do not start more checks.
    : > "${stamp}"
    local work="${lock}/work"
    # A global: the trap runs after this function's locals are gone.
    _MPKG_UPDATE_LOCK="${lock}"
    trap 'rm -rf "${_MPKG_UPDATE_LOCK}"' EXIT
    trap 'exit 130' INT TERM HUP

    local named=0
    (( ${#pkgs[@]} )) && named=1
    (( named )) || mapfile -t pkgs < <(mpkg::db_list)
    local p k
    local -a check=() own=()
    for p in "${pkgs[@]}"; do
        mpkg::db_installed "${p}" || { mpkg::warn "${p} is not installed"; continue; }
        k="$(mpkg::db_get "${p}" kind)"
        case "${k}" in
            meta)        ;;
            script)      own+=("${p}") ;;
            *)           check+=("${p}") ;;
        esac
    done

    (( auto )) || mpkg::head "checking ${#check[@]} package(s) for newer releases"
    local i=0
    for p in "${check[@]}"; do
        (
            v="$(mpkg::update_probe "${p}" "${work}/${p}")"
            printf '%s %s\n' "$?" "${v}" > "${work}/${p}.result"
        ) &
        (( ++i % MPKG_UPDATE_JOBS == 0 )) && wait
    done
    wait

    # Merge: a package checked now gets a fresh line (or none); every other
    # line is kept, so a failed check or a partial one forgets nothing.
    local f; f="$(mpkg::updates_file)"
    local tmp="${f}.tmp.$$" rc v have
    local -a behind=() failed=()
    declare -A fresh=()
    for p in "${check[@]}"; do
        read -r rc v < "${work}/${p}.result" 2>/dev/null || rc=1
        case "${rc}" in
            0) fresh[$p]=1
               have="$(mpkg::db_version "${p}")"
               [[ "${v}" != "${have}" ]] && behind+=("${p} ${have} ${v}") ;;
            3) ;;
            *) failed+=("${p}") ;;
        esac
    done
    {
        if [[ -f "${f}" ]]; then
            while read -r p have v; do
                [[ -n "${p}" && -z "${fresh[$p]:-}" ]] && mpkg::db_installed "${p}" \
                    && printf '%s %s %s\n' "${p}" "${have}" "${v}"
            done < "${f}"
        fi
        (( ${#behind[@]} )) && printf '%s\n' "${behind[@]}"
    } > "${tmp}" && mv -f "${tmp}" "${f}"

    (( auto )) && return 0

    local n=0
    while read -r p have v; do
        printf '  %-20s %-16s -> %s\n' "${p}" "${have}" "${v}"
        n=$(( n + 1 ))
    done < <(mpkg::updates_pending)
    if (( n )); then
        mpkg::say "${C_YEL}${n} upgrade(s) available.${C_RST} Install with: mpkg upgrade [pkg...]"
    else
        mpkg::ok "everything checked is up to date"
    fi
    (( ${#own[@]} )) && mpkg::say "  ${C_DIM}not checked, updated by their own installers: ${own[*]}${C_RST}"
    if (( ${#failed[@]} )); then
        mpkg::warn "could not check: ${failed[*]}$( (( MPKG_VERBOSE )) || printf ' (details: mpkg -v update %s)' "${failed[*]}")"
        if (( MPKG_VERBOSE )); then
            for p in "${failed[@]}"; do
                [[ -s "${work}/${p}/log" ]] || continue
                printf '  %s--- %s ---%s\n' "${C_DIM}" "${p}" "${C_RST}" >&2
                tail -n 10 "${work}/${p}/log" | sed 's/^/  | /' >&2
            done
        fi
        return 1
    fi
    return 0
}
