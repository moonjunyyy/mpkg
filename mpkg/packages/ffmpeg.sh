mpkg_inherit srccommon

MPKG_TITLE="FFmpeg"
MPKG_DESC="Audio/video converter and libav* libraries, with x264, opus and https"
MPKG_HOMEPAGE="https://ffmpeg.org/"
MPKG_DEPENDS=(openssl x264 opus)
# nasm assembles the x86 SIMD code; arm64 builds use the C compiler's assembler.
[[ "${_UARCH}" == x86_64 ]] && MPKG_DEPENDS+=(nasm)
MPKG_REQUIRES_CMD=(cc make pkg-config)

MPKG_LISTING_URL="https://ffmpeg.org/releases/"
MPKG_TAG_PATTERN='ffmpeg-[0-9]+\.[0-9]+(\.[0-9]+)?\.tar\.xz'
MPKG_TARBALL_URL='https://ffmpeg.org/releases/${tag}.tar.xz'
MPKG_TARBALL='${tag}.tar.xz'

# ffmpeg's configure ignores CFLAGS/LDFLAGS from the environment; the prefix's
# include and library paths have to go in through --extra-*. --enable-rpath
# lets ffmpeg find its own libav*.so without LD_LIBRARY_PATH.
MPKG_CONFIGURE_FLAGS=(
    --enable-shared
    --disable-static
    --disable-doc
    --enable-rpath
    '--extra-cflags=${_CFLAGS}'
    '--extra-ldflags=${_LDFLAGS}'
)

# Enable each external library only if it is really linkable, so a missing
# optional piece degrades the build instead of failing configure.
mpkg_configure() {
    if mpkg::have_shared_lib x264; then
        # libx264 is GPL; so is the resulting ffmpeg (GPLv3 with openssl).
        MPKG_CONFIGURE_FLAGS+=(--enable-gpl --enable-libx264)
    else
        mpkg::warn "libx264 not found; ffmpeg will not encode H.264"
    fi
    mpkg::have_shared_lib opus && MPKG_CONFIGURE_FLAGS+=(--enable-libopus)
    # OpenSSL 3 is Apache-2.0, which only (L)GPL *version 3* can take in.
    mpkg::have_shared_lib ssl  && MPKG_CONFIGURE_FLAGS+=(--enable-openssl --enable-version3)
    command -v nasm >/dev/null 2>&1 || MPKG_CONFIGURE_FLAGS+=(--disable-x86asm)
    mpkg_super configure
}

mpkg_verify() {
    local ff="${MPKG_SOFT}/${MPKG_DEST_NAME}/bin/ffmpeg"
    if ! "${ff}" -hide_banner -version >/dev/null 2>&1; then
        mpkg::err "the new ffmpeg does not start (missing libav*.so?)"
        return 1
    fi
    local enc
    enc="$("${ff}" -hide_banner -encoders 2>/dev/null)"
    [[ "${enc}" == *libx264* ]] && mpkg::step "H.264 encoding (libx264) available"
    [[ "${enc}" == *libopus* ]] && mpkg::step "Opus encoding (libopus) available"
    return 0
}
