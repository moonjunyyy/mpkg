# packages/pkgcommon.sh — root base class.
#
# Every other base class inherits from this one. It owns the parts that are the
# same for all install kinds: release discovery, the up-to-date test, linking
# into the prefix and temp-file cleanup. It deliberately has no mpkg_run: a
# package must inherit a concrete kind (srccommon, bincommon, tarcommon,
# scriptcommon, metacommon).

MPKG_KIND="abstract"

mpkg_run() {
    mpkg::err "package '${MPKG_NAME}' inherits no installer kind"
    mpkg::err "add e.g. 'mpkg_inherit srccommon' at the top of ${MPKG_NAME}.sh"
    return 1
}

# --- discovery --------------------------------------------------------------

# Scrape MPKG_LISTING_URL for MPKG_TAG_PATTERN, newest first, and take the
# first candidate whose artifact really exists. That HEAD request is what keeps
# release candidates and documentation-only tags (git-2.52.0-rc1, openssl
# alpha tags) from being selected and then 404-ing at download time.
mpkg_discover() {
    if [[ -z "${MPKG_LISTING_URL}" && -n "${MPKG_GITHUB_REPO:-}" ]]; then
        mpkg::github_discover
        return
    fi
    if [[ -z "${MPKG_LISTING_URL}" ]]; then
        mpkg::err "${MPKG_NAME}: no MPKG_LISTING_URL and no custom mpkg_discover"
        return 1
    fi

    local listing="${MPKG_NAME}-listing.html"
    MPKG_TMPFILES+=("${listing}")
    mpkg::download "${MPKG_LISTING_URL}" "${listing}" || return 1

    local cand url tried=0
    while IFS= read -r cand; do
        (( tried >= MPKG_TAG_CANDIDATES )) && break
        tried=$(( tried + 1 ))

        MPKG_TAG="$(mpkg::trim_tag "${cand}")"
        MPKG_VERSION="${MPKG_TAG#"${MPKG_NAME}"-}"
        [[ -n "${MPKG_ASSET}" ]] && MPKG_ASSET_FILE="$(mpkg::render "${MPKG_ASSET}")"

        local tmpl="${MPKG_VERIFY_URL}"
        [[ -z "${tmpl}" ]] && tmpl="${MPKG_TARBALL_URL}"
        [[ -z "${tmpl}" ]] && tmpl="${MPKG_ASSET_URL}"
        [[ -z "${tmpl}" ]] && return 0

        url="$(mpkg::render "${tmpl}")"
        if mpkg::url_exists "${url}"; then
            mpkg::dbg "selected ${MPKG_TAG}"
            return 0
        fi
        mpkg::dbg "rejecting ${MPKG_TAG}: no artifact at ${url}"
    done < <(mpkg::match_versions "${MPKG_TAG_PATTERN}" "${listing}")

    mpkg::err "${MPKG_NAME}: no usable release found at ${MPKG_LISTING_URL}"
    return 1
}

# Packages that set MPKG_GITHUB_REPO instead of a listing take the repository's
# latest release. The version is the first dotted number in the tag, so v1.2.3,
# release-2.1.13-stable and 3.7c all come out right.
mpkg::github_discover() {
    MPKG_TAG="$(mpkg::github_latest_tag "${MPKG_GITHUB_REPO}")" \
        || { mpkg::err "${MPKG_NAME}: no release found for github.com/${MPKG_GITHUB_REPO}"; return 1; }
    if [[ "${MPKG_TAG}" =~ ([0-9]+(\.[0-9]+)+[a-z]?) ]]; then
        MPKG_VERSION="${BASH_REMATCH[1]}"
    else
        MPKG_VERSION="${MPKG_TAG}"
    fi
    [[ -n "${MPKG_ASSET}" ]] && MPKG_ASSET_FILE="$(mpkg::render "${MPKG_ASSET}")"
    mpkg::dbg "selected ${MPKG_TAG}"
    return 0
}

# --- shared helpers ---------------------------------------------------------

# True when the recorded install already matches the discovered version and the
# package tree is still on disk. Being mpkg-recorded matters: a distro-provided
# binary of the same version is not a substitute for our own build.
mpkg::is_current() {
    [[ ${MPKG_FORCE:-0} -eq 1 ]] && return 1
    mpkg::db_installed "${MPKG_NAME}" || return 1
    [[ -n "${MPKG_VERSION}" ]] || return 1
    [[ "${MPKG_VERSION}" == "${MPKG_INSTALLED_VERSION}" ]] || return 1
    local d="${MPKG_DEST_NAME}"
    [[ -n "${d}" ]] || d="$(mpkg::render "${MPKG_DESTDIR}")"
    [[ -d "${MPKG_SOFT}/${d}" ]]
}

mpkg::report_versions() {
    mpkg::say "  installed: ${MPKG_INSTALLED_VERSION}    available: ${MPKG_VERSION:-?}"
}

mpkg_link() {
    cd "${MPKG_WORK}" || return 1
    # Replace the previous version's links before adding ours.
    mpkg::db_installed "${MPKG_NAME}" && mpkg::unlink "${MPKG_NAME}"
    mpkg::link "${MPKG_NAME}" "${MPKG_DEST_NAME}"
}

mpkg_cleanup() {
    cd "${MPKG_WORK}" 2>/dev/null || return 0
    [[ ${MPKG_KEEP_WORK:-0} -eq 1 ]] && return 0
    local f
    for f in "${MPKG_TMPFILES[@]}"; do
        [[ -n "${f}" && "${f}" != /* && "${f}" != *..* ]] && rm -rf -- "${f}"
    done
    return 0
}

# Delete the previous tree for this package once the new one is linked.
mpkg::drop_old_tree() {
    local old; old="$(mpkg::db_dest "${MPKG_NAME}" 2>/dev/null)"
    [[ -n "${old}" && "${old}" != "${MPKG_DEST_NAME}" && -d "${MPKG_SOFT}/${old}" ]] || return 0
    local users; users="$(mpkg::venv_refs "${old}" | tr '\n' ' ')"
    if [[ -n "${users// /}" ]]; then
        mpkg::step "kept ${old}: pinned by environment(s) ${users% }"
        return 0
    fi
    rm -rf "${MPKG_SOFT:?}/${old}"
    mpkg::step "removed superseded ${old}"
}
