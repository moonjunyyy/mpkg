mpkg_inherit srccommon

MPKG_TITLE="libyaml"
MPKG_DESC="YAML library, for Ruby's psych (which gem itself needs)"
MPKG_HOMEPAGE="https://pyyaml.org/wiki/LibYAML"
MPKG_PROBE_CMD=""
MPKG_REQUIRES_CMD=(cc make)

MPKG_LISTING_URL="https://pyyaml.org/download/libyaml/"
MPKG_TAG_PATTERN='yaml-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz'
MPKG_TARBALL_URL='https://pyyaml.org/download/libyaml/${tag}.tar.gz'
MPKG_DESTDIR='libyaml-${version}'

# Static and position-independent, for the same reason as zlib: psych.so
# takes libyaml.a in, and nothing in the prefix shadows a system libyaml.
MPKG_CONFIGURE_FLAGS=(--disable-shared --enable-static --with-pic)

mpkg_describe() {
    # The release's config.guess (2018) predates Apple silicon and guesses
    # arm-apple-darwin; name the build machine instead of letting it guess.
    [[ "${_OS}" == macos ]] && MPKG_CONFIGURE_FLAGS+=(--build="${_UARCH}-apple-darwin")
    return 0
}

# Tarballs are yaml-<version>; the package is libyaml.
mpkg_discover() {
    mpkg_super discover || return 1
    MPKG_VERSION="${MPKG_TAG#yaml-}"
}

mpkg_verify() {
    local dest="${MPKG_SOFT}/${MPKG_DEST_NAME}"
    [[ -f "${dest}/lib/libyaml.a" && -f "${dest}/include/yaml.h" ]] && return 0
    mpkg::err "libyaml.a or yaml.h is missing from ${dest}"
    return 1
}
