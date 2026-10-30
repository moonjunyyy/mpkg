mpkg_inherit gnucommon

MPKG_TITLE="GNU Autoconf"
MPKG_DESC="Configure-script generator"
MPKG_DEPENDS=(m4)
MPKG_PROVIDES_CMD=(autoconf autoheader)
MPKG_REQUIRES_CMD=(cc make perl)
