mpkg_inherit srccommon

MPKG_TITLE="Git"
MPKG_DESC="Distributed version control system"
MPKG_HOMEPAGE="https://git-scm.com/"
MPKG_PROBE_CMD="git"
MPKG_DEPENDS=(curl openssl)
# git cannot build without zlib.
mpkg::have_header zlib.h || MPKG_DEPENDS+=(zlib)
# Only with --with-optional: git builds without Rust, see mpkg::git_setup_rust.
MPKG_OPTDEPENDS=(rust)
MPKG_REQUIRES_CMD=(cc make)

MPKG_LISTING_URL="https://mirrors.edge.kernel.org/pub/software/scm/git/"
# Match the tarball name, not a bare tag: the listing also carries
# git-2.x.y-rc1.tar.gz and git-manpages-2.x.y.tar.gz, and picking either of
# those yields a download that 404s.
MPKG_TAG_PATTERN='git-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz'
MPKG_TARBALL_URL='https://mirrors.edge.kernel.org/pub/software/scm/git/${tag}.tar.gz'
# Git has no support for a separate object directory.
MPKG_INTREE=1

# Decide how to tell git's configure about libcurl, and make sure that answer
# will actually work.
#
# git's configure settles https support with AC_CHECK_LIB(curl,
# curl_global_init) -- it *links* a test program. If ${MPKG_PREFIX}/lib holds
# only libcurl.a (because the .so symlinks were never created) that link fails
# on zlib/zstd symbols, configure sets NO_CURL, and the resulting git has no
# git-remote-http/git-remote-https. `git clone https://...` then dies with
# "fatal: unable to find remote helper for 'https'".
mpkg::git_setup_curl() {
    if ! mpkg::have_shared_lib curl && mpkg::db_installed curl; then
        mpkg::warn "libcurl.so missing from the prefix; repairing curl's links"
        mpkg::link curl "$(mpkg::db_dest curl)" || true
    fi

    if mpkg::have_shared_lib curl; then
        MPKG_CONFIGURE_FLAGS+=(--with-curl="${MPKG_PREFIX}")
        mpkg::dbg "using libcurl from ${MPKG_PREFIX}"
    else
        mpkg::warn "no libcurl in ${MPKG_PREFIX}; falling back to the system one"
        MPKG_CONFIGURE_FLAGS+=(--with-curl)
    fi

    if mpkg::have_shared_lib ssl; then
        MPKG_CONFIGURE_FLAGS+=(--with-openssl="${MPKG_PREFIX}")
    else
        MPKG_CONFIGURE_FLAGS+=(--with-openssl)
    fi
}

# Since 2.52 git compiles Rust code (libgitcore.a, via `cargo build`) unless
# the make variable NO_RUST is set; configure has no switch for it. A machine
# without a working cargo -- none at all, or only rustup's shim with no
# toolchain installed -- would fail the build, so Rust is used only when cargo
# really runs. MPKG_GIT_RUST=yes|no overrides the probe. (Git 3.0 makes Rust
# mandatory; then this becomes a hard dependency on the rust package.)
mpkg::git_setup_rust() {
    local want="${MPKG_GIT_RUST:-auto}"
    if [[ "${want}" == auto ]]; then
        cargo --version >/dev/null 2>&1 && want=yes || want=no
    fi
    if [[ "${want}" == yes ]]; then
        mpkg::step "building with Rust ($(cargo --version 2>/dev/null))"
    else
        mpkg::step "building without Rust (NO_RUST)"
        MPKG_MAKE_VARS+=(NO_RUST=YesPlease)
    fi
}

mpkg_prepare() {
    mpkg::git_setup_curl
    mpkg::git_setup_rust
    mpkg_super prepare
}

# Refuse to call a git without https support "installed": that failure is
# invisible until the first clone, days later.
mpkg_verify() {
    local core="${MPKG_SOFT}/${MPKG_DEST_NAME}/libexec/git-core"
    if [[ ! -e "${core}/git-remote-https" ]]; then
        mpkg::err "git was built without https support (no git-remote-https)"
        mpkg::err "libcurl was not linkable when configure ran."
        mpkg::err "run 'mpkg doctor', then 'mpkg install --force curl git'."
        return 1
    fi
    mpkg::step "https remote helper present"

    if [[ -n "${MPKG_CA_BUNDLE}" ]]; then
        "${MPKG_PREFIX}/bin/git" config --global --replace-all http.sslCAInfo "${MPKG_CA_BUNDLE}" 2>/dev/null || true
    fi
    if ! mpkg::run "${MPKG_PREFIX}/bin/git" ls-remote --exit-code \
            https://github.com/git/git.git HEAD; then
        mpkg::warn "git ls-remote over https did not succeed; see ${MPKG_LOG}"
    else
        mpkg::step "https clone path verified"
    fi
    return 0
}
