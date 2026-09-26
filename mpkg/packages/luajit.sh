mpkg_inherit srccommon

MPKG_TITLE="LuaJIT"
MPKG_DESC="Just-in-time compiler for Lua 5.1"
MPKG_HOMEPAGE="https://luajit.org/"
MPKG_PROBE_CMD="luajit"
MPKG_REQUIRES_CMD=(cc make)

# LuaJIT stopped cutting releases: v2.1 is a rolling branch, and its version is
# 2.1.<unix time of the last commit> (what `luajit -v` prints). Discovery reads
# the branch's commit feed -- no API call, so no rate limit -- and builds that
# exact commit, so the version and the source cannot disagree.
MPKG_GITHUB_REPO="LuaJIT/LuaJIT"
MPKG_LUAJIT_BRANCH="v2.1"
MPKG_TARBALL_URL='https://github.com/${MPKG_GITHUB_REPO}/archive/${tag}.tar.gz'
MPKG_TARBALL='LuaJIT-${tag}.tar.gz'
MPKG_SRCDIR='LuaJIT-${tag}'
MPKG_DESTDIR='luajit-${version}'
MPKG_INTREE=1

# No configure script. PREFIX is needed at build time too: it is compiled into
# the default package.path. CFLAGS is left alone; LuaJIT's Makefile picks its
# own and warns against overriding them.
MPKG_CONFIGURE=""
MPKG_MAKE_VARS=('PREFIX=${MPKG_SOFT}/luajit-${version}')

mpkg_describe() {
    if [[ "${_OS}" == "macos" ]]; then
        # Required by the Makefile on macOS; it refuses to guess.
        MPKG_MAKE_VARS+=("MACOSX_DEPLOYMENT_TARGET=$(sw_vers -productVersion | cut -d. -f1,2)")
    fi
    return 0
}

# ISO-8601 UTC (2026-09-08T08:43:01Z) -> seconds since the epoch.
mpkg::luajit_epoch() {
    date -u -d "$1" +%s 2>/dev/null \
        || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null
}

mpkg_discover() {
    local feed="${MPKG_NAME}-commits.atom" sha stamp epoch
    MPKG_TMPFILES+=("${feed}")
    mpkg::download "https://github.com/${MPKG_GITHUB_REPO}/commits/${MPKG_LUAJIT_BRANCH}.atom" "${feed}" \
        || return 1

    # The first <entry> is the branch head; the feed's own <updated> precedes it.
    sha="$(grep -oE 'Grit::Commit/[0-9a-f]{40}' "${feed}" | head -n1)"
    sha="${sha##*/}"
    stamp="$(sed -n '/<entry>/,/<\/entry>/{s/.*<updated>\([^<]*\)<\/updated>.*/\1/p;}' "${feed}" | head -n1)"
    epoch="$(mpkg::luajit_epoch "${stamp}")"
    [[ -n "${sha}" && -n "${epoch}" ]] \
        || { mpkg::err "${MPKG_NAME}: could not read the ${MPKG_LUAJIT_BRANCH} head from the commit feed"; return 1; }

    MPKG_TAG="${sha}"
    MPKG_VERSION="${MPKG_LUAJIT_BRANCH#v}.${epoch}"
    mpkg::dbg "selected ${sha} (${stamp})"
}

mpkg_verify() {
    local bin="${MPKG_SOFT}/${MPKG_DEST_NAME}/bin/luajit"
    if ! "${bin}" -e 'assert(jit.status())' >/dev/null 2>&1; then
        mpkg::err "the new luajit does not run, or its JIT compiler is disabled"
        return 1
    fi
    mpkg::step "$("${bin}" -v 2>&1 | head -n1)"
}
