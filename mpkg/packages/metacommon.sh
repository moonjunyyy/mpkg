# packages/metacommon.sh — base class for packages that only pull in others.
# `mpkg install workspace` resolves the whole bootstrap through the normal
# dependency solver instead of a hardcoded list.

mpkg_inherit pkgcommon

MPKG_KIND="meta"
MPKG_UNVERSIONED=1

mpkg_run() {
    MPKG_VERSION="meta"
    MPKG_DEST_NAME=""
    MPKG_STATUS="installed"
    mpkg::step "${#MPKG_DEPENDS[@]} dependencies satisfied"
    return 0
}

mpkg_link() { return 0; }
