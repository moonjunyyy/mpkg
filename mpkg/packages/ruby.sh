mpkg_inherit srccommon

MPKG_TITLE="Ruby"
MPKG_DESC="Ruby interpreter, gem and bundler"
MPKG_HOMEPAGE="https://www.ruby-lang.org/"
MPKG_PROBE_CMD="ruby"
MPKG_DEPENDS=(openssl curl)
MPKG_REQUIRES_CMD=(cc make)

MPKG_LISTING_URL="https://cache.ruby-lang.org/pub/ruby/"
MPKG_TARBALL_URL='https://cache.ruby-lang.org/pub/ruby/${version%.*}/ruby-${version}.tar.gz'
MPKG_TARBALL='ruby-${version}.tar.gz'
MPKG_SRCDIR='ruby-${version}'
MPKG_DESTDIR='ruby-${version}'
MPKG_CONFIGURE_FLAGS=(
    --disable-install-doc
    --enable-load-relative
    --enable-shared
    --with-openssl-dir='${MPKG_PREFIX}'
)

# Ruby files releases under per-minor-version subdirectories, so finding the
# newest patch release needs a second listing fetch.
mpkg_discover() {
    local listing="ruby-listing.html" patch="ruby-patch.html"
    MPKG_TMPFILES+=("${listing}" "${patch}")
    mpkg::download "${MPKG_LISTING_URL}" "${listing}" || return 1

    local -a minors
    mapfile -t minors < <(grep -oE '[0-9]+\.[0-9]+/' "${listing}" | mpkg::vsort -r -u)

    local ver newest
    for ver in "${minors[@]}"; do
        mpkg::download "${MPKG_LISTING_URL}${ver}" "${patch}" || continue
        newest="$(mpkg::match_versions "ruby-${ver%/}\.[0-9]+\.tar\.gz" "${patch}" | head -n1)"
        rm -f "${patch}"
        if [[ -n "${newest}" ]]; then
            MPKG_VERSION="$(printf '%s' "${newest}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
            MPKG_TAG="ruby-${MPKG_VERSION}"
            return 0
        fi
    done
    mpkg::err "could not determine the newest Ruby release"
    return 1
}
