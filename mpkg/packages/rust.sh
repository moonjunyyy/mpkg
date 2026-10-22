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

mpkg_env() {
    # shellcheck source=/dev/null
    [[ -s "${HOME}/.cargo/env" ]] && . "${HOME}/.cargo/env"
    environment_prepend "PATH" "${HOME}/.cargo/bin"
    return 0
}

mpkg_remove() {
    mpkg::warn "run 'rustup self uninstall' to remove the toolchain itself"
}
