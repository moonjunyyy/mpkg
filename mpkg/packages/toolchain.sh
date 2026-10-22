# The minimum needed to fetch and build anything else: a working https client
# and a git that can actually clone over https.

mpkg_inherit metacommon

MPKG_TITLE="Toolchain"
MPKG_DESC="openssl, curl, jq and git -- the bootstrap floor"
MPKG_DEPENDS=(openssl curl jq git)
