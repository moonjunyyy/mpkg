# mpkg / lib/doctor.sh — checking the prefix for breakage, and repairing it.
#
# The link check is the core of it. Every installed package has a manifest of
# the links it owns; each entry is compared with what is actually in the
# prefix, which is read with a single find (mpkg::prefix_links):
#
#   missing     the link is gone                         relink
#   elsewhere   a link is there but points somewhere else relink
#   shadowed    a real file or directory sits in its place relink --force
#   damaged     the link is right, but the file it points at is gone from
#               the store tree, so relinking cannot help  reinstall
#
# plus links nobody owns that point at nothing: into the store (pruned), or
# anywhere else (reported, never touched).

MPKG_DOC_PROBLEMS=0
MPKG_DOC_WARNINGS=0
declare -A MPKG_DOC_LINKS=()     # prefix path -> link target, every link in the prefix
declare -A MPKG_DOC_CLAIMED=()   # prefix paths some manifest owns
MPKG_DOC_RELINK=()               # base packages a relink repairs
MPKG_DOC_FORCE_RELINK=()         # ... only with --force (a file is in the way)
MPKG_DOC_REINSTALL=()            # base packages whose tree is damaged or gone
MPKG_DOC_ENV_RELINK=()           # "<env> <pkg>" pairs a relink repairs

mpkg::doc_problem() { mpkg::err "$*"; MPKG_DOC_PROBLEMS=$(( MPKG_DOC_PROBLEMS + 1 )); }
mpkg::doc_warn()    { mpkg::warn "$*"; MPKG_DOC_WARNINGS=$(( MPKG_DOC_WARNINGS + 1 )); }

mpkg::doc_read_links() {
    local t target tmp
    MPKG_DOC_LINKS=()
    MPKG_DOC_CLAIMED=()
    # Through a file: from a pipe, bash reads a byte per system call, which is
    # seconds for a big prefix; a regular file it reads in blocks.
    tmp="$(mktemp "${TMPDIR:-/tmp}/mpkg-links.XXXXXX")" || return 1
    mpkg::prefix_links > "${tmp}"
    while IFS= read -r -d '' t && IFS= read -r -d '' target; do
        MPKG_DOC_LINKS[$t]="${target}"
    done < "${tmp}"
    rm -f "${tmp}"
}

# doc_manifest <label> <into> <tree-root> <manifest>
# Compare one manifest with the prefix. Prints what is wrong and sets
# MPKG_DOC_VERDICT to ok | relink | force | reinstall (the worst found).
mpkg::doc_manifest() {
    local label="$1" into="$2" root="$3" manifest="$4"
    local rel t want cur
    local missing=0 elsewhere=0 shadowed=0 damaged=0
    local -a eg=()

    while IFS= read -r rel; do
        [[ -n "${rel}" ]] || continue
        t="${into}/${rel}"
        want="${root}/${rel}"
        MPKG_DOC_CLAIMED[$t]=1
        if [[ -n "${MPKG_DOC_LINKS[$t]+set}" ]]; then
            cur="${MPKG_DOC_LINKS[$t]}"
            # -ef: the same file under another spelling of the prefix is fine.
            if [[ "${cur}" != "${want}" ]] && ! [[ "${t}" -ef "${want}" ]]; then
                elsewhere=$(( elsewhere + 1 ))
                (( ${#eg[@]} < 3 )) && eg+=("${t} -> ${cur} (should be ${want})")
            elif [[ ! -e "${t}" ]]; then
                damaged=$(( damaged + 1 ))
                (( ${#eg[@]} < 3 )) && eg+=("${t} -> ${cur} (no such file in the tree)")
            fi
        elif [[ -e "${t}" ]]; then
            shadowed=$(( shadowed + 1 ))
            (( ${#eg[@]} < 3 )) && eg+=("${t} is a real file, not a link")
        else
            missing=$(( missing + 1 ))
            (( ${#eg[@]} < 3 )) && eg+=("${t} is missing")
        fi
    done < "${manifest}"

    local bad=$(( missing + elsewhere + shadowed + damaged ))
    MPKG_DOC_VERDICT="ok"
    (( bad == 0 )) && return 0

    local what=""
    (( missing ))   && what+=", ${missing} missing"
    (( elsewhere )) && what+=", ${elsewhere} pointing elsewhere"
    (( shadowed ))  && what+=", ${shadowed} replaced by files"
    (( damaged ))   && what+=", ${damaged} dangling"
    mpkg::doc_problem "${label}: ${bad} broken link(s): ${what#, }"
    local e
    for e in "${eg[@]}"; do mpkg::say "      ${e}"; done
    (( bad > ${#eg[@]} )) && mpkg::say "      ... and $(( bad - ${#eg[@]} )) more"

    if   (( damaged ));  then MPKG_DOC_VERDICT="reinstall"
    elif (( shadowed )); then MPKG_DOC_VERDICT="force"
    else                      MPKG_DOC_VERDICT="relink"
    fi
}

mpkg::doc_tools() {
    mpkg::head "build tools"
    local t
    for t in cc "${MPKG_MAKE}" tar; do
        if command -v "${t}" >/dev/null 2>&1; then mpkg::ok "${t}"
        else mpkg::doc_problem "${t} is missing"; fi
    done
}

mpkg::doc_database() {
    mpkg::head "database"
    local p dest n=0 before="${MPKG_DOC_PROBLEMS}"
    while IFS= read -r p; do
        n=$(( n + 1 ))
        dest="$(mpkg::db_dest "${p}")"
        [[ -z "${dest}" ]] && continue
        if [[ ! -d "${MPKG_SOFT}/${dest}" ]]; then
            mpkg::doc_problem "${p}: its tree ${MPKG_SOFT}/${dest} is gone"
            MPKG_DOC_REINSTALL+=("${p}")
        elif [[ ! -f "$(mpkg::db_files "${p}")" ]]; then
            mpkg::doc_problem "${p}: installed but never linked (no link manifest)"
            MPKG_DOC_RELINK+=("${p}")
        fi
    done < <(mpkg::db_list)
    (( MPKG_DOC_PROBLEMS == before )) && mpkg::ok "${n} package(s), every recorded tree present"
}

mpkg::doc_links() {
    mpkg::head "links"
    mpkg::doc_read_links
    local p dest manifest before="${MPKG_DOC_PROBLEMS}" n=0
    while IFS= read -r p; do
        dest="$(mpkg::db_dest "${p}")"
        manifest="$(mpkg::db_files "${p}")"
        # A missing tree or manifest is the database check's to report.
        [[ -n "${dest}" && -d "${MPKG_SOFT}/${dest}" && -f "${manifest}" ]] || continue
        n=$(( n + $(wc -l < "${manifest}") ))
        mpkg::doc_manifest "${p}" "${MPKG_PREFIX}" "${MPKG_SOFT}/${dest}" "${manifest}"
        case "${MPKG_DOC_VERDICT}" in
            relink)    MPKG_DOC_RELINK+=("${p}") ;;
            force)     MPKG_DOC_FORCE_RELINK+=("${p}") ;;
            reinstall) MPKG_DOC_REINSTALL+=("${p}") ;;
        esac
    done < <(mpkg::db_list)

    local e
    while IFS= read -r e; do
        while IFS= read -r p; do
            dest="$(mpkg::venv_get "${e}" "${p}" dest)"
            manifest="$(mpkg::venv_rec "${e}" "${p}").files"
            if [[ ! -d "${MPKG_SOFT}/${dest}" ]]; then
                mpkg::doc_problem "environment ${e}: ${p} tree ${dest} is gone (mpkg venv update ${e} ${p})"
                continue
            fi
            [[ -f "${manifest}" ]] || continue
            n=$(( n + $(wc -l < "${manifest}") ))
            mpkg::doc_manifest "environment ${e}: ${p}" "$(mpkg::venv_dir "${e}")" \
                "${MPKG_SOFT}/${dest}" "${manifest}"
            [[ "${MPKG_DOC_VERDICT}" == relink ]] && MPKG_DOC_ENV_RELINK+=("${e} ${p}")
        done < <(mpkg::venv_pkgs "${e}")
    done < <(mpkg::venv_names)
    (( MPKG_DOC_PROBLEMS == before )) && mpkg::ok "${n} link(s), every one in place"

    # Dangling links no manifest owns. Into the store: left by a package that
    # is gone, safe to prune. Anywhere else: not ours to delete.
    local t store=() other=()
    for t in "${!MPKG_DOC_LINKS[@]}"; do
        [[ -n "${MPKG_DOC_CLAIMED[$t]:-}" || -e "${t}" ]] && continue
        [[ "${t}" == "${MPKG_PREFIX}/ssl/cert.pem" ]] && continue   # the trust store check's
        if [[ "${MPKG_DOC_LINKS[$t]}" == "${MPKG_SOFT}/"* ]]; then store+=("${t}")
        else other+=("${t}")
        fi
    done
    if (( ${#store[@]} )); then
        mpkg::doc_problem "${#store[@]} dangling link(s) into the store that no package owns (mpkg prune)"
        mpkg::doc_examples "${store[@]}"
        MPKG_DOC_PRUNE=1
    fi
    if (( ${#other[@]} )); then
        mpkg::doc_warn "${#other[@]} dangling link(s) mpkg did not make; left alone:"
        mpkg::doc_examples "${other[@]}"
    fi
}

mpkg::doc_examples() {
    local -a l
    mapfile -t l < <(printf '%s\n' "$@" | sort | head -n 5)
    local t
    for t in "${l[@]}"; do mpkg::say "      ${t} -> ${MPKG_DOC_LINKS[$t]}"; done
    (( $# > 5 )) && mpkg::say "      ... and $(( $# - 5 )) more"
}

mpkg::doc_trust() {
    mpkg::head "trust store"
    if [[ -n "${MPKG_CA_BUNDLE}" ]]; then
        mpkg::ok "CA bundle: ${MPKG_CA_BUNDLE}"
    else
        mpkg::doc_problem "no CA bundle found; every https download will fail verification"
    fi
    local cert="${MPKG_PREFIX}/ssl/cert.pem"
    if [[ -e "${cert}" ]]; then
        mpkg::ok "openssl default CAfile is present"
    elif mpkg::db_installed openssl; then
        if [[ ${MPKG_FIX} -eq 1 && -n "${MPKG_CA_BUNDLE}" ]]; then
            mkdir -p "${MPKG_PREFIX}/ssl/certs"
            ln -sfn "${MPKG_CA_BUNDLE}" "${cert}"
            mpkg::ok "repaired: ${cert} -> ${MPKG_CA_BUNDLE}"
        elif [[ -L "${cert}" ]]; then
            mpkg::doc_problem "${cert} -> $(readlink "${cert}") is a broken link (run: mpkg doctor --fix)"
        else
            mpkg::doc_problem "${cert} is missing (run: mpkg doctor --fix)"
        fi
    fi
}

# Only the libraries of packages that are installed: libcurl is not expected
# from a prefix that has openssl and no curl.
mpkg::doc_libs() {
    local lib pkg shown=0
    for lib in curl:curl ssl:openssl crypto:openssl; do
        pkg="${lib#*:}"; lib="${lib%%:*}"
        mpkg::db_installed "${pkg}" || continue
        (( shown++ )) || mpkg::head "shared libraries"
        if mpkg::have_shared_lib "${lib}"; then
            mpkg::ok "lib${lib} is linkable"
        else
            mpkg::doc_problem "lib${lib} is missing from the prefix (it comes with ${pkg})"
        fi
    done
}

mpkg::doc_git() {
    mpkg::db_installed git || return 0
    mpkg::head "git https support"
    local g="${MPKG_PREFIX}/bin/git"
    if [[ ! -x "${g}" ]]; then
        mpkg::doc_problem "git is installed, but ${g} $( [[ -L "${g}" ]] && echo 'is a broken link' || echo 'is missing')"
    elif [[ -e "$("${g}" --exec-path)/git-remote-https" ]]; then
        mpkg::ok "git-remote-https is present"
    else
        mpkg::doc_problem "this git cannot speak https (no git-remote-https); fix: mpkg install --force git"
    fi
}

mpkg::doc_repair() {
    local p e dest
    (( ${#MPKG_DOC_RELINK[@]} + ${#MPKG_DOC_FORCE_RELINK[@]} + ${#MPKG_DOC_REINSTALL[@]} \
       + ${#MPKG_DOC_ENV_RELINK[@]} + ${MPKG_DOC_PRUNE:-0} )) || return 0

    if (( ! MPKG_FIX )); then
        mpkg::say ""
        mpkg::say "To repair:"
        (( ${#MPKG_DOC_RELINK[@]} + ${#MPKG_DOC_ENV_RELINK[@]} + ${MPKG_DOC_PRUNE:-0} )) \
            && mpkg::say "  mpkg doctor --fix                  relinks and prunes what it can"
        (( ${#MPKG_DOC_FORCE_RELINK[@]} )) \
            && mpkg::say "  mpkg link --force ${MPKG_DOC_FORCE_RELINK[*]}   moves the files in the way to *.mpkg-orig"
        (( ${#MPKG_DOC_REINSTALL[@]} )) \
            && mpkg::say "  mpkg install --force --no-deps ${MPKG_DOC_REINSTALL[*]}   (or: mpkg doctor --fix)"
        return 0
    fi

    mpkg::head "repairing"
    for p in "${MPKG_DOC_RELINK[@]}"; do
        dest="$(mpkg::db_dest "${p}")"
        mpkg::step "relinking ${p}"
        mpkg::unlink "${p}" >/dev/null
        mpkg::link "${p}" "${dest}" >/dev/null && mpkg::ok "relinked ${p}" \
            || mpkg::err "${p}: relink incomplete"
    done
    for e in "${MPKG_DOC_ENV_RELINK[@]}"; do
        p="${e#* }"; e="${e%% *}"
        mpkg::step "relinking ${p} in ${e}"
        mpkg::venv_link_pkg "${e}" "${p}" "$(mpkg::venv_get "${e}" "${p}" dest)" \
            "$(mpkg::venv_get "${e}" "${p}" version)" >/dev/null \
            && mpkg::ok "relinked ${p} in ${e}" || mpkg::err "${p} in ${e}: relink incomplete"
    done
    (( ${MPKG_DOC_PRUNE:-0} )) && mpkg::prune_links
    for p in "${MPKG_DOC_FORCE_RELINK[@]}"; do
        mpkg::warn "${p}: files are in the way of its links; not moving them without: mpkg link --force ${p}"
    done
    if (( ${#MPKG_DOC_REINSTALL[@]} )); then
        mpkg::step "reinstalling ${MPKG_DOC_REINSTALL[*]} (downloads and rebuilds)"
        MPKG_FORCE=1 MPKG_NO_DEPS=1 mpkg::install "${MPKG_DOC_REINSTALL[@]}"
    fi
    mpkg::say ""
    mpkg::say "Repairs done; checking again."
    mpkg::say ""
}

mpkg::doc_run() {
    MPKG_DOC_PROBLEMS=0 MPKG_DOC_WARNINGS=0 MPKG_DOC_PRUNE=0
    MPKG_DOC_RELINK=() MPKG_DOC_FORCE_RELINK=() MPKG_DOC_REINSTALL=() MPKG_DOC_ENV_RELINK=()
    mpkg::head "prefix"
    mpkg::say "  ${MPKG_PREFIX}   (os=${_OS} arch=${_ARCH} jobs=${_NPROCESSORS})"
    mpkg::doc_tools
    mpkg::doc_database
    mpkg::doc_links
    mpkg::doc_trust
    mpkg::doc_libs
    mpkg::doc_git
}

mpkg::doctor() {
    mpkg::doc_run
    # Repair, then look again: what is reported last is the state left behind.
    if (( MPKG_FIX && MPKG_DOC_PROBLEMS )); then
        mpkg::doc_repair
        MPKG_FIX=0 mpkg::doc_run
    else
        mpkg::doc_repair
    fi

    mpkg::say ""
    local w=""
    (( MPKG_DOC_WARNINGS )) && w=", ${MPKG_DOC_WARNINGS} warning(s)"
    if (( MPKG_DOC_PROBLEMS == 0 )); then
        mpkg::say "${C_GRN}No problems found${C_RST}${w}."
    else
        mpkg::say "${C_RED}${MPKG_DOC_PROBLEMS} problem(s) found${C_RST}${w}."
        return 1
    fi
}
