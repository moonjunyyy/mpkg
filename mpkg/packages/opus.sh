mpkg_inherit srccommon

MPKG_TITLE="Opus"
MPKG_DESC="Opus audio codec library, for ffmpeg's libopus"
MPKG_HOMEPAGE="https://opus-codec.org/"
MPKG_PROBE_CMD=""
MPKG_REQUIRES_CMD=(cc make)

MPKG_LISTING_URL="https://downloads.xiph.org/releases/opus/"
MPKG_TAG_PATTERN='opus-[0-9]+\.[0-9]+(\.[0-9]+)?\.tar\.gz'
MPKG_TARBALL_URL='https://downloads.xiph.org/releases/opus/${tag}.tar.gz'
MPKG_CONFIGURE_FLAGS=(--disable-doc --disable-extra-programs)

mpkg_verify() {
    mpkg::have_shared_lib opus && return 0
    mpkg::err "libopus.so is not linkable from ${MPKG_PREFIX}/lib"
    return 1
}
