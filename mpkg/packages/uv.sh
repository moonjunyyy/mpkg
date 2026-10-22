mpkg_inherit scriptcommon

MPKG_TITLE="uv"
MPKG_DESC="Fast Python package and interpreter manager"
MPKG_HOMEPAGE="https://docs.astral.sh/uv/"
MPKG_PROBE_CMD="uv"
MPKG_DEPENDS=(curl)

MPKG_GUARD_CMD="uv"
MPKG_VERSION_CMD="uv --version"
MPKG_SCRIPT_URL="https://astral.sh/uv/install.sh"
MPKG_SCRIPT_ENV=(UV_NO_MODIFY_PATH=1 "UV_INSTALL_DIR=${MPKG_PREFIX}/bin")

mpkg_post_install() {
    mpkg::step "installing a managed Python"
    mpkg::run uv python install || mpkg::warn "uv could not install Python; continuing"
    return 0
}
