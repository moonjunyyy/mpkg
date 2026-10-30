# mpkg / lib/engine.sh — install / remove orchestration.

# Status set by a class's mpkg_run: installed | current | skipped
MPKG_STATUS=""

mpkg::work_enter() {
    mkdir -p "${MPKG_WORK}" || return 1
    cd "${MPKG_WORK}" || return 1
}

# A failed build can leave a half-installed tree in the store, which a later
# build of the same version would install on top of. Delete it -- unless it is
# a tree the database or an environment points at (a forced reinstall of the
# current version), or --keep-work asked for the evidence to stay.
mpkg::discard_partial_tree() {
    local d="${MPKG_DEST_NAME:-}"
    [[ -n "${d}" && "${d}" != */* && -d "${MPKG_SOFT}/${d}" ]] || return 0
    [[ ${MPKG_KEEP_WORK:-0} -eq 1 ]] && return 0
    mpkg::store_in_use "${d}" && return 0
    rm -rf "${MPKG_SOFT:?}/${d}"
    mpkg::step "removed the incomplete ${d} from the store"
}

mpkg::install_one() {
    local name="$1" dest kind

    mpkg::class_load "${name}" || return 1
    mpkg::check_requires "${name}" || return 1

    MPKG_LOG="${MPKG_LOGDIR}/${name}.log"
    : > "${MPKG_LOG}"
    compute_build_flags

    mpkg::head "${MPKG_TITLE}"

    # Prefer what the database says over probing $PATH: a system-provided git
    # must not make mpkg think its own git is already installed.
    if mpkg::db_installed "${name}"; then
        MPKG_INSTALLED_VERSION="$(mpkg::db_version "${name}")"
    else
        MPKG_INSTALLED_VERSION="$(mpkg::probe_version "${MPKG_PROBE_CMD}")"
    fi
    [[ -n "${MPKG_INSTALLED_VERSION}" ]] || MPKG_INSTALLED_VERSION="0.0.0"

    if [[ ${MPKG_DRY_RUN:-0} -eq 1 ]]; then
        mpkg::say "  would install ${name} (kind=${MPKG_KIND}, present=${MPKG_INSTALLED_VERSION})"
        return 0
    fi

    mpkg::work_enter || { mpkg::err "cannot use work directory ${MPKG_WORK}"; return 1; }

    MPKG_STATUS=""
    if ! mpkg_run; then
        mpkg::discard_partial_tree
        mpkg::err "${name}: installation failed (log: mpkg log ${name})"
        return 1
    fi

    case "${MPKG_STATUS}" in
        current)
            # Present already (an installer-script package finds its tool on
            # the system): recorded all the same, so that its environment is
            # kept and 'mpkg remove' knows it.
            mpkg::db_installed "${name}" \
                || mpkg::db_put "${name}" "${MPKG_INSTALLED_VERSION}" "" "${MPKG_KIND:-unknown}" \
                                "${MPKG_DEPENDS[@]:-}"
            mpkg::ok "already up to date (${MPKG_INSTALLED_VERSION})"
            ;;
        skipped)
            mpkg::ok "nothing to do"
            ;;
        *)
            dest="${MPKG_DEST_NAME:-}"
            kind="${MPKG_KIND:-unknown}"
            mpkg::db_put "${name}" "${MPKG_VERSION:-unknown}" "${dest}" "${kind}" \
                         "${MPKG_DEPENDS[@]:-}"
            mpkg::optional post_install \
                || mpkg::warn "${name}: post-install steps reported errors"
            mpkg::optional_strict verify \
                || { mpkg::err "${name}: the installed package failed its own check"; return 1; }
            mpkg::ok "installed ${MPKG_VERSION:-}"
            ;;
    esac
    # Last, because post-install may create what the environment points at
    # (nvm's first node). The packages built after this one see it too.
    mpkg::shell_write
    return 0
}

mpkg::install() {
    local -a wanted=("$@")
    local p failed=() done_n=0

    mpkg::resolve "${wanted[@]}" || return 1

    # A dependency that is already recorded is satisfied; an explicitly named
    # package is always revisited so `mpkg install git` can refresh it.
    local -a plan=() satisfied=()
    for p in "${MPKG_ORDER[@]}"; do
        if mpkg::db_installed "${p}" \
           && [[ ${MPKG_FORCE_ALL:-0} -eq 0 ]] \
           && [[ " ${wanted[*]} " != *" ${p} "* ]]; then
            satisfied+=("${p}")
            continue
        fi
        plan+=("${p}")
    done

    (( ${#satisfied[@]} )) && mpkg::say "Already satisfied: ${satisfied[*]}"
    # Satisfied dependencies are not revisited; their environment (mason needs
    # nvm's npm) came with env.sh when mpkg started. A prefix from before
    # packages declared their environment has no fragments yet: write them.
    if [[ ! -d "$(mpkg::shell_dir)" && -n "$(mpkg::db_list)" && ${MPKG_DRY_RUN:-0} -eq 0 ]]; then
        mpkg::say "Writing the shell environment of the installed packages"
        mpkg::shell_sync
    fi
    if (( ${#plan[@]} == 0 )); then
        mpkg::say "Nothing to do."
        return 0
    fi
    mpkg::say "Plan (${#plan[@]}): ${plan[*]}"
    mpkg::say ""

    for p in "${plan[@]}"; do
        if mpkg::install_one "${p}"; then
            done_n=$(( done_n + 1 ))
        else
            failed+=("${p}")
            [[ ${MPKG_KEEP_GOING:-0} -eq 1 ]] || break
        fi
        mpkg::say ""
    done

    if (( ${#failed[@]} )); then
        mpkg::err "failed: ${failed[*]}"
        return 1
    fi
    mpkg::say "${C_GRN}Done.${C_RST} ${done_n} package(s) processed."
}

mpkg::remove_one() {
    local name="$1" dest rdeps

    mpkg::db_installed "${name}" || { mpkg::warn "${name} is not installed"; return 0; }

    rdeps="$(mpkg::db_reverse_deps "${name}" | tr '\n' ' ')"
    if [[ -n "${rdeps// /}" && ${MPKG_FORCE:-0} -eq 0 ]]; then
        mpkg::err "${name} is required by: ${rdeps}"
        mpkg::err "re-run with --force to remove it anyway"
        return 1
    fi

    mpkg::head "Removing ${name}"
    if [[ ${MPKG_DRY_RUN:-0} -eq 1 ]]; then
        mpkg::say "  would unlink and delete ${MPKG_SOFT}/$(mpkg::db_dest "${name}")"
        return 0
    fi

    # Give the class a chance to clean up outside the prefix (script packages).
    if mpkg::class_load "${name}" >/dev/null 2>&1; then
        mpkg::optional remove
    fi

    mpkg::unlink "${name}"
    dest="$(mpkg::db_dest "${name}")"
    local users; users="$(mpkg::venv_refs "${dest}" | tr '\n' ' ')"
    if [[ -n "${users// /}" ]]; then
        mpkg::step "kept ${MPKG_SOFT}/${dest}: still used by environment(s) ${users% }"
    elif [[ -n "${dest}" && -d "${MPKG_SOFT}/${dest}" ]]; then
        rm -rf "${MPKG_SOFT:?}/${dest}"
        mpkg::step "deleted ${MPKG_SOFT}/${dest}"
    fi
    mpkg::db_forget "${name}"
    mpkg::shell_forget "${name}"
    mpkg::ok "removed ${name}"
}

mpkg::upgrade() {
    local -a targets=("$@")
    if (( ${#targets[@]} == 0 )); then
        mapfile -t targets < <(mpkg::db_list)
    fi
    (( ${#targets[@]} == 0 )) && { mpkg::say "nothing installed"; return 0; }
    MPKG_NO_DEPS=1 mpkg::install "${targets[@]}"
}
