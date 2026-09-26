mpkg_inherit srccommon

MPKG_TITLE="x264"
MPKG_DESC="H.264 encoder library, for ffmpeg's libx264"
MPKG_HOMEPAGE="https://www.videolan.org/developers/x264.html"
MPKG_DEPENDS=(jq)
[[ "${_UARCH}" == x86_64 ]] && MPKG_DEPENDS+=(nasm)
MPKG_REQUIRES_CMD=(cc make)

# x264 does not tag releases; its 'stable' branch is what distributions ship.
# The version is the branch head's commit date plus its short hash.
MPKG_X264_API="https://code.videolan.org/api/v4/projects/videolan%2Fx264/repository/branches/stable"
MPKG_TARBALL_URL='https://code.videolan.org/videolan/x264/-/archive/${MPKG_X264_SHA}/x264-${MPKG_X264_SHA}.tar.bz2'
MPKG_TARBALL='x264-${MPKG_X264_SHA}.tar.bz2'
MPKG_SRCDIR='x264-${MPKG_X264_SHA}'
MPKG_DESTDIR='x264-${version}'
MPKG_INTREE=1
MPKG_CONFIGURE_FLAGS=(--enable-shared --enable-pic)

mpkg_discover() {
    local branch="x264-branch.json"
    MPKG_TMPFILES+=("${branch}")
    mpkg::download "${MPKG_X264_API}" "${branch}" || return 1
    MPKG_X264_SHA="$(jq -r '.commit.id // empty' "${branch}")"
    local date; date="$(jq -r '.commit.committed_date // empty' "${branch}" | cut -c1-10 | tr -d -)"
    [[ -n "${MPKG_X264_SHA}" && -n "${date}" ]] \
        || { mpkg::err "x264: could not read the stable branch head"; return 1; }
    MPKG_VERSION="${date}.${MPKG_X264_SHA:0:7}"
    MPKG_TAG="x264-${MPKG_VERSION}"
}
