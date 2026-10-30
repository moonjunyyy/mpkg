mpkg_inherit srccommon

MPKG_TITLE="Ruby"
MPKG_DESC="Ruby interpreter, gem and bundler"
MPKG_HOMEPAGE="https://www.ruby-lang.org/"
MPKG_PROBE_CMD="ruby"
MPKG_DEPENDS=(openssl curl)
MPKG_REQUIRES_CMD=(cc make)
# What Ruby's own extensions link, where the system lacks it: macOS has zlib
# in its SDK but no libyaml, minimal Linux images often have neither's headers.
# Without them configure skips psych / zlib with one line in the log, and the
# first `gem install` fails.
mpkg::have_header yaml.h || MPKG_DEPENDS+=(libyaml)
mpkg::have_header zlib.h || MPKG_DEPENDS+=(zlib)

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

# An extension whose library was missing is skipped, not an error. psych and
# zlib are what gem itself needs, openssl what https needs: a Ruby without
# them is not "installed".
mpkg_verify() {
    local ruby="${MPKG_SOFT}/${MPKG_DEST_NAME}/bin/ruby" e
    local -a missing=()
    for e in psych zlib openssl; do
        "${ruby}" -r"${e}" -e 1 >/dev/null 2>&1 || missing+=("${e}")
    done
    if (( ${#missing[@]} )); then
        mpkg::err "ruby was built without: ${missing[*]} (mpkg log ruby)"
        return 1
    fi
    mpkg::step "psych, zlib and openssl load"
}
