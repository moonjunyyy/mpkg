mpkg_inherit srccommon

MPKG_TITLE="LuaRocks"
MPKG_DESC="Package manager for Lua modules"
MPKG_HOMEPAGE="https://luarocks.org/"
MPKG_PROBE_CMD="luarocks"
MPKG_DEPENDS=(lua)
MPKG_REQUIRES_CMD=(cc make)

MPKG_LISTING_URL="https://luarocks.org/releases/"
MPKG_TAG_PATTERN='luarocks-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz'
MPKG_TARBALL_URL='https://luarocks.org/releases/${tag}.tar.gz'
MPKG_INTREE=1

mpkg_describe() {
    MPKG_CONFIGURE_FLAGS=(--with-lua="${MPKG_PREFIX}")
    local v
    v="$(mpkg::probe_version lua | cut -d. -f1,2)"
    [[ "${v}" != "0.0" ]] && MPKG_CONFIGURE_FLAGS+=(--lua-version="${v}")
    return 0
}
