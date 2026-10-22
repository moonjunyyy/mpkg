mpkg_inherit pwmtcommon

MPKG_TITLE="zathura-pdf-poppler"
MPKG_DESC="PDF support for zathura, through poppler"
MPKG_DEPENDS+=(zathura poppler)

# Into this package's own tree; linking puts it in ${MPKG_PREFIX}/lib/zathura,
# which is where zathura looks.
MPKG_CONFIGURE_FLAGS=('-Dplugindir=${MPKG_SOFT}/${MPKG_DEST_NAME}/lib/zathura')

mpkg_verify() {
    local out
    out="$("${MPKG_PREFIX}/bin/zathura" --version 2>/dev/null)"
    [[ "${out}" == *pdf-poppler* ]] && { mpkg::step "zathura loads the pdf-poppler plugin"; return 0; }
    mpkg::err "zathura does not list the pdf-poppler plugin"
    return 1
}
