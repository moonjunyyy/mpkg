mpkg_inherit gnucommon

MPKG_TITLE="GNU Bison"
MPKG_DESC="Parser generator"
MPKG_DEPENDS=(m4)
MPKG_PROVIDES_CMD=(bison yacc)
MPKG_REQUIRES_CMD=(cc make)
