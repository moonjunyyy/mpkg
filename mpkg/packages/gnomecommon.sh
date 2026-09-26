# packages/gnomecommon.sh — base class for GNOME projects on download.gnome.org
# (GTK), built with Meson.
#
# Every project there has a cache.json listing each release and its tarball.
# GNOME numbers stable series with an even minor (4.20, 4.22); odd minors are
# development snapshots, so only even ones are taken. A package can narrow the
# major version with MPKG_GNOME_MAJOR.

mpkg_inherit mesoncommon

MPKG_KIND="gnome"
MPKG_DEPENDS+=(jq)
MPKG_GNOME_MAJOR='[0-9]+'

mpkg_discover() {
    local project="${MPKG_GNOME_PROJECT:-${MPKG_NAME}}"
    local base="https://download.gnome.org/sources/${project}"
    local cache="${MPKG_NAME}-cache.json" path
    MPKG_TMPFILES+=("${cache}")

    command -v jq >/dev/null 2>&1 || { mpkg::err "jq is required to read ${base}/cache.json"; return 1; }
    mpkg::download "${base}/cache.json" "${cache}" || return 1

    MPKG_VERSION="$(jq -r --arg p "${project}" '.[2][$p][]' "${cache}" \
        | grep -E "^${MPKG_GNOME_MAJOR}\.[0-9]*[02468]\.[0-9]+$" | sort -Vr | head -n1)"
    [[ -n "${MPKG_VERSION}" ]] || { mpkg::err "${MPKG_NAME}: no stable release in ${base}/cache.json"; return 1; }

    path="$(jq -r --arg p "${project}" --arg v "${MPKG_VERSION}" \
        '.[1][$p][$v]["tar.xz"] // empty' "${cache}")"
    [[ -n "${path}" ]] || { mpkg::err "${MPKG_NAME}: ${MPKG_VERSION} has no tar.xz"; return 1; }

    MPKG_TAG="${project}-${MPKG_VERSION}"
    MPKG_TARBALL_URL="${base}/${path}"
    mpkg::dbg "selected ${MPKG_TAG}"
}
