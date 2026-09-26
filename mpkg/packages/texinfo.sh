mpkg_inherit gnucommon

MPKG_TITLE="GNU Texinfo"
MPKG_DESC="Documentation system; provides makeinfo"
MPKG_PROBE_CMD="makeinfo"
MPKG_REQUIRES_CMD=(cc make perl)
