mpkg_inherit bincommon

MPKG_TITLE="jq"
MPKG_DESC="Command line JSON processor"
MPKG_HOMEPAGE="https://jqlang.github.io/jq/"
MPKG_PROBE_CMD="jq"

MPKG_LISTING_URL="https://github.com/jqlang/jq/tags"
MPKG_TAG_PATTERN='jq-[0-9]+\.[0-9]+\.[0-9]+'
MPKG_ASSET='jq-${_OS}-${_ARCH}'
MPKG_ASSET_URL='https://github.com/jqlang/jq/releases/download/${tag}/${asset}'
