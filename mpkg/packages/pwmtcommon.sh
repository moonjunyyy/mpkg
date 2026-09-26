# packages/pwmtcommon.sh — base class for the pwmt.org projects (girara,
# zathura and its plugins). They all publish the same way, so everything
# follows from the package name, like gnucommon:
#
#   https://pwmt.org/projects/<name>/download/<name>-<version>.tar.xz
#
# Versions are dates (2026.07.18), and a plugin requires the zathura of the
# same date or newer, so the three are best upgraded together.

mpkg_inherit mesoncommon

MPKG_KIND="pwmt"
MPKG_PROBE_CMD=""

mpkg_describe() {
    [[ -n "${MPKG_HOMEPAGE}" ]]     || MPKG_HOMEPAGE="https://pwmt.org/projects/${MPKG_NAME}/"
    [[ -n "${MPKG_LISTING_URL}" ]]  || MPKG_LISTING_URL="https://pwmt.org/projects/${MPKG_NAME}/download/"
    [[ -n "${MPKG_TAG_PATTERN}" ]]  || MPKG_TAG_PATTERN="${MPKG_NAME}"'-[0-9]+(\.[0-9]+)+\.tar\.xz'
    [[ -n "${MPKG_TARBALL_URL}" ]]  || MPKG_TARBALL_URL="${MPKG_LISTING_URL}"'${tag}.tar.xz'
}
