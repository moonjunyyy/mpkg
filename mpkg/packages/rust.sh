mpkg_inherit scriptcommon

MPKG_TITLE="Rust"
MPKG_DESC="Rust toolchain, installed through rustup"
MPKG_HOMEPAGE="https://www.rust-lang.org/"
MPKG_PROBE_CMD="rustc"
MPKG_DEPENDS=(curl)

MPKG_GUARD_CMD="cargo"
MPKG_VERSION_CMD="rustc --version"
MPKG_SCRIPT_URL="https://sh.rustup.rs"
MPKG_SCRIPT_RUNNER=(sh)
MPKG_SCRIPT_ARGS=(--no-modify-path --default-toolchain stable -y)

MPKG_ENV=('path PATH ${CARGO_HOME:-${HOME}/.cargo}/bin')

mpkg_remove() {
    mpkg::warn "run 'rustup self uninstall' to remove the toolchain itself"
}
