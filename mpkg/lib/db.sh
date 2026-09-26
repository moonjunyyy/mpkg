# mpkg / lib/db.sh — the installed-package database.
#
# One flat key=value record per package under $MPKG_DB/<name>, plus a
# <name>.files manifest of every path linked into the prefix. Deliberately
# plain text: the bootstrap must not depend on sqlite3 being present.

mpkg::db_record() { printf '%s/%s' "${MPKG_DB}" "$1"; }
mpkg::db_files()  { printf '%s/%s.files' "${MPKG_DB}" "$1"; }

mpkg::db_installed() { [[ -f "$(mpkg::db_record "$1")" ]]; }

mpkg::db_get() {
    local name="$1" key="$2" rec
    rec="$(mpkg::db_record "${name}")"
    [[ -f "${rec}" ]] || return 1
    sed -n "s/^${key}=//p" "${rec}" | head -n1
}

mpkg::db_version() { mpkg::db_get "$1" version; }
mpkg::db_dest()    { mpkg::db_get "$1" dest; }

mpkg::db_put() {
    local name="$1" version="$2" dest="$3" kind="$4"; shift 4
    local rec; rec="$(mpkg::db_record "${name}")"
    {
        printf 'name=%s\n'     "${name}"
        printf 'version=%s\n'  "${version}"
        printf 'dest=%s\n'     "${dest}"
        printf 'kind=%s\n'     "${kind}"
        printf 'depends=%s\n'  "$*"
        printf 'date=%s\n'     "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'prefix=%s\n'   "${MPKG_PREFIX}"
    } > "${rec}"
}

mpkg::db_forget() {
    rm -f "$(mpkg::db_record "$1")" "$(mpkg::db_files "$1")"
}

mpkg::db_list() {
    local rec name
    shopt -s nullglob
    for rec in "${MPKG_DB}"/*; do
        [[ "${rec}" == *.files ]] && continue
        name="$(basename "${rec}")"
        printf '%s\n' "${name}"
    done
    shopt -u nullglob
}

# Which installed packages declare <name> as a dependency?
mpkg::db_reverse_deps() {
    local target="$1" p deps
    while IFS= read -r p; do
        deps="$(mpkg::db_get "${p}" depends)"
        [[ " ${deps} " == *" ${target} "* ]] && printf '%s\n' "${p}"
    done < <(mpkg::db_list)
}
