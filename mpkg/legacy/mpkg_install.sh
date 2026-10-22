# Bootstrap development environment
# set -euo pipefail

# ============================================================================
# Environment Setup
# ============================================================================

environment_prepend() {
    local var_name="$1"
    local new_path="$2"
    local current="${!var_name:-}"
    # No-op if already present
    if [[ ":${current}:" == *":${new_path}:"* ]]; then
        return 0
    fi
    if [[ -z "$current" ]]; then
        export "${var_name}"="${new_path}"
    else
        export "${var_name}"="${new_path}:${current}"
    fi
}

_PREFIX="${HOME}/.local"
export _PREFIX

mkdir -p "${_PREFIX}"/{bin,lib,include,share,soft,ssl}

environment_prepend "PATH"            "/usr/bin"
environment_prepend "PATH"            "${_PREFIX}/bin"
environment_prepend "PATH"            "${HOME}/.cargo/bin"
environment_prepend "CPATH"           "${_PREFIX}/include"
environment_prepend "CXXPATH"         "${_PREFIX}/include"
environment_prepend "LIBRARY_PATH"    "/usr/lib64"
environment_prepend "LIBRARY_PATH"    "/usr/lib"
environment_prepend "LIBRARY_PATH"    "${_PREFIX}/lib64"
environment_prepend "LIBRARY_PATH"    "${_PREFIX}/lib"
environment_prepend "LD_LIBRARY_PATH" "/usr/lib64"
environment_prepend "LD_LIBRARY_PATH" "/usr/lib"
environment_prepend "LD_LIBRARY_PATH" "${_PREFIX}/lib64"
environment_prepend "LD_LIBRARY_PATH" "${_PREFIX}/lib"
environment_prepend "MANPATH"         "/usr/share/man"
environment_prepend "MANPATH"         "${_PREFIX}/share/man"
environment_prepend "PKG_CONFIG_PATH" "/usr/lib64/pkgconfig"
environment_prepend "PKG_CONFIG_PATH" "/usr/lib/pkgconfig"
environment_prepend "PKG_CONFIG_PATH" "${_PREFIX}/lib64/pkgconfig"
environment_prepend "PKG_CONFIG_PATH" "${_PREFIX}/lib/pkgconfig"

INSTALLATION_PATH="${_PREFIX}/soft"
export INSTALLATION_PATH

echo "Installation prefix:    ${_PREFIX}"
echo "Package directory:      ${INSTALLATION_PATH}"
echo ""

# ============================================================================
# Utility Functions
# ============================================================================

get_installed_version() {
    local command="$1"
    local output
    output=$(("$command" --version 2>/dev/null || "$command" -v 2>/dev/null || echo "") \
        | tr '[:upper:]' '[:lower:]')
    if [[ "$output" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "0.0.0"
    fi
}

# Compute CFLAGS/CXXFLAGS/LDFLAGS from environment path variables.
# Sets _CFLAGS, _CXXFLAGS, _LDFLAGS in the calling scope.
compute_build_flags() {
    _CFLAGS=$(  echo "${CPATH:-}"        | tr ':' '\n' | grep -v '^$' | sed 's/^/-I/' | tr '\n' ' ')
    _CXXFLAGS=$(echo "${CXXPATH:-}"      | tr ':' '\n' | grep -v '^$' | sed 's/^/-I/' | tr '\n' ' ')
    _LDFLAGS=$( echo "${LIBRARY_PATH:-}" | tr ':' '\n' | grep -v '^$' | sed 's/^/-L/' | tr '\n' ' ')
}

# Expand a package template string. Templates are single-quoted in specs so
# they are expanded here, once the version is known. Available placeholders:
#   ${name} ${tag} ${version} ${asset}  plus any exported var (${_OS}, ${PREFIX}, ...)
render() {
    local name="${PKG_NAME}"
    local tag="${PKG_TAG}"
    local version="${PKG_VERSION}"
    local asset="${PKG_ASSET_FILE:-}"
    eval "printf '%s' \"$1\""
}

# Run stage <s>: the package-specific override pkg_<name>_<s> if it exists,
# otherwise the shared default stage_<s>.
run_stage() {
    local stage="$1"
    if declare -f "${PKG_FN}_${stage}" >/dev/null 2>&1; then
        "${PKG_FN}_${stage}"
    else
        "stage_${stage}"
    fi
}

# Run stage <s> only if the package defines it; never fails the install.
run_optional_stage() {
    local stage="$1"
    if declare -f "${PKG_FN}_${stage}" >/dev/null 2>&1; then
        "${PKG_FN}_${stage}"
    fi
    return 0
}

# Load the declarative spec for the package being installed.
load_spec() {
    local spec_fn="$1"
    if ! declare -f "${spec_fn}" >/dev/null 2>&1; then
        echo "  Error: no spec function '${spec_fn}' for package '${PKG_NAME}'" >&2
        return 1
    fi
    "${spec_fn}"
}

pkg_banner() {
    hash -r
    echo "=== Installing ${PKG_TITLE} ==="
}

# Banner + workdir + installed-version probe. Sets PKG_INSTALLED_VERSION.
pkg_begin() {
    pkg_banner
    cd "${_ORIGIN_PWD}/workdir" || return 1
    PKG_INSTALLED_VERSION=$(get_installed_version "${PKG_PROBE_CMD}")
    echo "  Current version: ${PKG_INSTALLED_VERSION}"
}

pkg_is_current() {
    [[ -n "${PKG_VERSION}" && "${PKG_VERSION}" == "${PKG_INSTALLED_VERSION}" ]]
}

pkg_clean_tmpfiles() {
    if [[ ${#PKG_TMPFILES[@]} -gt 0 ]]; then
        rm -f "${PKG_TMPFILES[@]}"
    fi
    return 0
}

# ============================================================================
# Package Metadata
# ============================================================================
#
# Every package is installed by one of four shared drivers, selected by
# PACKAGE_KIND below. A driver runs a fixed sequence of stages; a package only
# describes what is different about it:
#
#   1. A spec function `pkg_<name>_spec` that sets declarative PKG_* fields
#      (URLs, patterns, configure flags, make targets, ...).
#   2. Optionally, stage override functions `pkg_<name>_<stage>` that replace a
#      single default stage. Overrides may call the default (stage_<stage>) and
#      then adjust the result.
#
# Kinds:
#   gnu       source build, spec derived from GNU_VERSION_PATTERN (no spec fn)
#   source    source build driven by pkg_<name>_spec
#   binary    single pre-built executable from a GitHub release
#   prebuilt  pre-built tarball unpacked into ${INSTALLATION_PATH}
#   script    upstream installer script (nvm, rustup, ...)
#
# Source-build stages, in order:
#   discover -> fetch -> prepare_build -> configure -> build -> install
#            -> link -> cleanup -> post_install (optional)

declare -A PACKAGE_KIND
PACKAGE_KIND=(
    # GNU FTP packages — standard autoconf/make build, fully table-driven
    [autoconf]=gnu
    [make]=gnu
    [bison]=gnu
    [texinfo]=gnu
    [m4]=gnu
    [coreutils]=gnu
    [binutils]=gnu
    [glibc]=gnu

    # Source builds with a package-specific twist (see each pkg_<name>_spec)
    [openssl]=source    # 'Configure' (capital C) + special install targets
    [curl]=source       # underscored tag format (curl-X_Y_Z); needs openssl path
    [git]=source        # in-tree build (no separate objdir)
    [ruby]=source       # version discovery from two-level directory hierarchy
    [lua]=source        # no configure; platform-specific make targets
    [luarocks]=source   # in-tree configure/make

    # Pre-built artifacts
    [jq]=binary
    [neovim]=prebuilt

    # Upstream installer scripts
    [nodejs]=script     # via NVM
    [rust]=script       # via rustup
    [uv]=script         # via astral.sh installer
    [oh-my-zsh]=script  # via ohmyzsh installer + plugin clones
    [starship]=script   # via starship installer
)

# Tag version regex per GNU package (some publish X.Y, others X.Y.Z).
declare -A GNU_VERSION_PATTERN
GNU_VERSION_PATTERN=(
    [autoconf]='[0-9]+\.[0-9]+'
    [make]='[0-9]+\.[0-9]+\.[0-9]+'
    [bison]='[0-9]+\.[0-9]+\.[0-9]+'
    [texinfo]='[0-9]+\.[0-9]+\.[0-9]+'
    [m4]='[0-9]+\.[0-9]+\.[0-9]+'
    [coreutils]='[0-9]+\.[0-9]+\.[0-9]+'
    [binutils]='[0-9]+\.[0-9]+\.[0-9]+'
    [glibc]='[0-9]+\.[0-9]+'
)

# Optional extra ./configure flags per GNU package, space separated.
declare -A GNU_CONFIGURE_FLAGS
GNU_CONFIGURE_FLAGS=()

GNU_MIRROR="https://ftp.kaist.ac.kr/gnu"

# ============================================================================
# Shared Build Stages
# ============================================================================

# Find the newest tag on a release listing page and derive the version from it.
stage_discover() {
    local listing="${PKG_NAME}_listing.html"
    PKG_TMPFILES+=("${listing}")
    download_url "${PKG_LISTING_URL}" "${listing}" || return 1
    PKG_TAG=$(extract_version "${PKG_TAG_PATTERN}" "${listing}")
    PKG_VERSION="${PKG_TAG#${PKG_NAME}-}"
}

# Download and unpack the source tarball. Resolves the rendered path fields.
stage_fetch() {
    PKG_TARBALL_FILE=$(render "${PKG_TARBALL}")
    PKG_SRC_DIR=$(render "${PKG_SRCDIR}")
    PKG_DEST_NAME=$(render "${PKG_PKGDIR}")

    download_url "$(render "${PKG_TARBALL_URL}")" "${PKG_TARBALL_FILE}" || return 1

    echo "  → Extracting..."
    tar -xzf "${PKG_TARBALL_FILE}" || return 1
}

# Create the install prefix and enter the build directory.
stage_prepare_build() {
    mkdir -p "${INSTALLATION_PATH}/${PKG_DEST_NAME}" || return 1
    if [[ "${PKG_INTREE}" -eq 1 ]]; then
        cd "${PKG_SRC_DIR}" || return 1
    else
        mkdir -p objdir || return 1
        cd objdir || return 1
    fi
}

stage_configure() {
    # Packages without a configure script (e.g. Lua) set PKG_CONFIGURE="".
    [[ -z "${PKG_CONFIGURE}" ]] && return 0

    local script
    if [[ "${PKG_INTREE}" -eq 1 ]]; then
        script="./${PKG_CONFIGURE}"
    else
        script="../${PKG_SRC_DIR}/${PKG_CONFIGURE}"
    fi

    echo "  → Configuring..."
    CFLAGS="${_CFLAGS}" CXXFLAGS="${_CXXFLAGS}" LDFLAGS="${_LDFLAGS}" \
    "${script}" \
        --prefix="${INSTALLATION_PATH}/${PKG_DEST_NAME}" \
        "${PKG_CONFIGURE_FLAGS[@]}" \
        >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then echo "  !! Configure Failed !!"; return 1; fi
}

# Expand the placeholders in PKG_MAKE_VARS into the array MAKE_VARS.
render_make_vars() {
    local var
    MAKE_VARS=()
    for var in "${PKG_MAKE_VARS[@]}"; do
        MAKE_VARS+=("$(render "${var}")")
    done
}

stage_build() {
    local -a MAKE_VARS
    render_make_vars
    echo "  → Building..."
    make -j"${_NPROCESSORS}" "${PKG_MAKE_TARGETS[@]}" "${MAKE_VARS[@]}" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then echo "  !! Build Failed !!"; return 1; fi
}

stage_install() {
    local -a MAKE_VARS
    render_make_vars
    echo "  → Installing..."
    make "${MAKE_VARS[@]}" "${PKG_INSTALL_TARGETS[@]}" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then echo "  !! Install Failed !!"; return 1; fi
}

stage_link() {
    cd "${_ORIGIN_PWD}/workdir" || return 1
    link_package "${PKG_DEST_NAME}"
}

stage_cleanup() {
    rm -rf objdir "${PKG_SRC_DIR}" "${PKG_TARBALL_FILE}"
    pkg_clean_tmpfiles
}

# ============================================================================
# Drivers
# ============================================================================

# Reset every PKG_* field to its default, so a spec only states what differs.
# These are deliberately global: stage overrides read and adjust them.
pkg_init() {
    PKG_NAME="$1"
    PKG_FN="pkg_${PKG_NAME//-/_}"

    PKG_TITLE="${PKG_NAME}"
    PKG_PROBE_CMD="${PKG_NAME}"
    PKG_TAG=""
    PKG_VERSION=""
    PKG_INSTALLED_VERSION="0.0.0"
    PKG_TMPFILES=()

    # Where to look for releases, and what the artifact is called.
    PKG_LISTING_URL=""
    PKG_TAG_PATTERN=""
    PKG_TARBALL_URL=""
    PKG_TARBALL='${tag}.tar.gz'
    PKG_SRCDIR='${tag}'
    PKG_PKGDIR='${tag}'
    PKG_TARBALL_FILE=""
    PKG_SRC_DIR=""
    PKG_DEST_NAME=""

    # How to build it.
    PKG_INTREE=0
    PKG_CONFIGURE="configure"
    PKG_CONFIGURE_FLAGS=()
    PKG_MAKE_TARGETS=()
    PKG_MAKE_VARS=()
    PKG_INSTALL_TARGETS=(install)

    # Pre-built artifacts (binary / prebuilt kinds).
    PKG_ASSET=""
    PKG_ASSET_URL=""
    PKG_ASSET_FILE=""
    PKG_ASSET_STEM=""

    # Upstream installer scripts (script kind).
    PKG_GUARD_CMD=""
    PKG_GUARD_DIR=""
    PKG_VERSION_CMD=""
    PKG_SCRIPT_URL=""
    PKG_SCRIPT_FILE="install_${PKG_NAME//-/_}.sh"
    PKG_SCRIPT_RUNNER=(bash)
    PKG_SCRIPT_ARGS=()
    PKG_SCRIPT_ENV=()
}

# Header, installed version, latest version, up-to-date check.
# Returns 0 to continue, 2 when already up to date, 1 on error.
pkg_resolve_version() {
    pkg_begin || return 1
    run_stage discover || return 1
    echo "  Latest version:  ${PKG_VERSION}"
    if pkg_is_current; then
        echo "  ✓ Already up to date"
        pkg_clean_tmpfiles
        echo ""
        return 2
    fi
}


pkg_finish() {
    echo "  ✓ Installed: ${PKG_VERSION}"
    echo ""
    run_optional_stage post_install
}

# ============================================================================
# Package Dispatch
# ============================================================================

install_pkg() {
    local name="$1"
    local kind="${PACKAGE_KIND[${name}]:-}"

    case "${kind}" in
        gnu)      install_source_package   "${name}" pkg_gnu_spec ;;
        source)   install_source_package   "${name}" ;;
        binary)   install_binary_package   "${name}" ;;
        prebuilt) install_prebuilt_package "${name}" ;;
        script)   install_script_package   "${name}" ;;
        "")
            echo "  Error: unknown package '${name}'" >&2
            return 1
            ;;
        *)
            echo "  Error: unknown install kind '${kind}' for package '${name}'" >&2
            return 1
            ;;
    esac
}

# ============================================================================
# Package Specs
# ============================================================================
#
# ============================================================================
# Main Installation
# ============================================================================

main() {
    echo "========================================"
    echo "  Development Environment Bootstrap"
    echo "========================================"
    echo ""

    

    # Core utilities
    install_pkg "jq"
    # install_pkg "bison"
    # install_pkg "m4"
    # install_pkg "texinfo"
    # install_pkg "make"
    # install_pkg "binutils"
    # install_pkg "glibc"
    # install_pkg "coreutils"
    install_pkg "autoconf"
    install_pkg "openssl"
    install_pkg "curl"
    install_pkg "git"

    # Programming languages
    install_pkg "ruby"
    install_pkg "lua"
    install_pkg "luarocks"
    install_pkg "nodejs"
    install_pkg "rust"
    install_pkg "uv"

    # Shell and editor
    install_pkg "oh-my-zsh"
    install_pkg "neovim"
    install_neovim_config
    install_pkg "starship"

    # Cleanup
    cd "${_ORIGIN_PWD}" || true
    rm -rf "${_ORIGIN_PWD}/workdir"

    cat > ~/.zshrc <<EOF
export PATH="${PATH}"
export CPATH="${CPATH}"
export CXXPATH="${CXXPATH}"
export LIBRARY_PATH="${LIBRARY_PATH}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}"

export ZSH="${HOME}/.oh-my-zsh"
export ZSH_THEME="robbyrussell"
export plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source \${ZSH}/oh-my-zsh.sh

# Starship prompt
export STARSHIP_CONFIG="${HOME}/.config/starship/jetpack.toml"
eval "\$(starship init zsh)"

# Rust
source "${HOME}/.cargo/env"

# NVM
export NVM_DIR="${HOME}/.nvm"
[ -s "\${NVM_DIR}/nvm.sh" ] && source "\${NVM_DIR}/nvm.sh"
EOF
    # if [[ "${SHELL}" =~ /bin/zsh ]]; then
    #     echo "  → Changing default shell to zsh..."
    #     source ~/.zshrc
    #     chsh -s /bin/zsh
    # fi
    echo "========================================"
    echo "  ✓ Installation Complete!"
    echo "========================================"
}

main "$@"
