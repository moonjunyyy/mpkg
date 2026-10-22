# The PDF rendering library, built for its GLib binding (poppler-glib), which
# is what zathura-pdf-poppler uses. The command-line utilities (pdftotext,
# pdfinfo, ...) come along.

mpkg_inherit cmakecommon

MPKG_TITLE="Poppler"
MPKG_DESC="PDF rendering library, with the GLib binding and command-line utils"
MPKG_HOMEPAGE="https://poppler.freedesktop.org/"
MPKG_PROBE_CMD="pdfinfo"
MPKG_REQUIRES_CMD+=(pkg-config)

MPKG_LISTING_URL="https://poppler.freedesktop.org/"
MPKG_TAG_PATTERN='poppler-[0-9]+\.[0-9]+\.[0-9]+\.tar\.xz'
MPKG_TARBALL_URL='https://poppler.freedesktop.org/${tag}.tar.xz'

MPKG_CONFIGURE_FLAGS=(
    -DENABLE_GLIB=ON
    -DENABLE_UTILS=ON
    -DENABLE_CPP=ON
    -DENABLE_QT5=OFF
    -DENABLE_QT6=OFF
    -DENABLE_BOOST=OFF
    -DENABLE_GPGME=OFF
    -DENABLE_GOBJECT_INTROSPECTION=OFF
    -DENABLE_GTK_DOC=OFF
    -DBUILD_GTK_TESTS=OFF
    -DBUILD_QT5_TESTS=OFF
    -DBUILD_QT6_TESTS=OFF
    -DBUILD_CPP_TESTS=OFF
    -DBUILD_MANUAL_TESTS=OFF
)

# Poppler stops at configure when an optional library it defaults to is
# missing, so each one is switched on only if pkg-config can see it.
mpkg_configure() {
    local opt pc
    for opt in LIBOPENJPEG:libopenjp2 LCMS:lcms2 LIBCURL:libcurl LIBTIFF:libtiff-4 \
               LIBJPEG:libjpeg NSS3:nss; do
        pc="${opt#*:}"
        if pkg-config --exists "${pc}"; then
            MPKG_CONFIGURE_FLAGS+=("-DENABLE_${opt%%:*}=ON")
        else
            mpkg::step "${pc} not found; building without it"
            MPKG_CONFIGURE_FLAGS+=("-DENABLE_${opt%%:*}=OFF")
        fi
    done
    mpkg_super configure
}

mpkg_verify() {
    mpkg::have_shared_lib poppler-glib && return 0
    mpkg::err "libpoppler-glib.so is not linkable from ${MPKG_PREFIX}/lib (glib or cairo missing?)"
    return 1
}
