# Bootstrap development environment
# Installs: jq, openssl, curl, git, ruby, lua, node, rust, uv, oh-my-zsh, neovim, starship

# set -euo pipefail

# ============================================================================
# Initial Setup
# ============================================================================

_ORIGIN_PWD=$(pwd)
mkdir -p ./workdir
cd ./workdir
_SCRIPT_DIR="$(pwd -P)"

# ============================================================================
# System Detection
# ============================================================================

detect_os() {
    local os
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$os" in
        darwin) echo "macos" ;;
        linux)  echo "linux" ;;
        *)      echo "$os" ;;
    esac
}

detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)        echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *)             echo "$arch" ;;
    esac
}

detect_nproc() {
    local os="$1"
    if [ "$os" = "macos" ]; then
        sysctl -n hw.ncpu
    else
        nproc
    fi
}

_OS=$(detect_os)
_ARCH=$(detect_arch)
_NPROCESSORS=$(detect_nproc "$_OS")
export _OS
export _ARCH
export _NPROCESSORS

echo "CPU cores:                ${_NPROCESSORS}"
echo "Detected OS:              ${_OS}"
echo "Detected Architecture:    ${_ARCH}"
echo ""

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

download_url() {
    local url="$1"
    local output="$2"
    echo "  → Downloading: $(basename "$output")"
    if command -v curl &>/dev/null; then
        curl -fsSL -o "${output}" "${url}"
    elif command -v wget &>/dev/null; then
        wget -q -O "${output}" "${url}"
    else
        echo "  Error: neither curl nor wget available" >&2
        return 1
    fi
}

extract_version() {
    local pattern="$1"
    local file="$2"
    grep -oE "$pattern" "$file" | sort -Vr | head -n1
}

link_package() {
    local package_name="$1"
    local pkg_path="${INSTALLATION_PATH}/${package_name}"
    while IFS= read -r -d '' file; do
        local relative_path="${file#${pkg_path}/}"
        local target="${_PREFIX}/${relative_path}"
        local target_dir
        target_dir=$(dirname "${target}")
        mkdir -p "${target_dir}"
        if [ -L "${target}" ]; then
            echo "  Warning: replacing existing symlink: ${target}" >&2
            rm -f "${target}"
        fi
        if [ -e "${target}" ]; then
            echo "  Error: collision at ${target}, unlink first." >&2
            return 1
        fi
        ln -sf "${file}" "${target}"
    done < <(find "${pkg_path}" -type f -print0 | sort -z)
}

unlink_package() {
    local package_name="$1"
    local pkg_path="${INSTALLATION_PATH}/${package_name}"
    while IFS= read -r -d '' file; do
        local relative_path="${file#${pkg_path}/}"
        local target="${_PREFIX}/${relative_path}"
        [ -L "${target}" ] && rm -f "${target}"
    done < <(find "${pkg_path}" -type f -print0 | sort -z)
}

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

# Build and install a package from source.
# Usage: install_source_package <name> [spec_function]
install_source_package() {
    pkg_init "$1"
    # Flags are recomputed per package: earlier installs may extend CPATH etc.
    compute_build_flags
    load_spec "${2:-${PKG_FN}_spec}" || return 1

    pkg_resolve_version
    case $? in 2) return 0 ;; 0) ;; *) return 1 ;; esac

    run_stage fetch         || return 1
    run_stage prepare_build || return 1
    run_stage configure     || return 1
    run_stage build         || return 1
    run_stage install       || return 1
    run_stage link          || return 1
    run_stage cleanup

    pkg_finish
}

# Install a single pre-built executable from a GitHub release.
install_binary_package() {
    pkg_init "$1"
    load_spec "${PKG_FN}_spec" || return 1

    pkg_resolve_version
    case $? in 2) return 0 ;; 0) ;; *) return 1 ;; esac

    PKG_ASSET_FILE=$(render "${PKG_ASSET}")
    PKG_DEST_NAME=$(render "${PKG_PKGDIR}")
    download_url "$(render "${PKG_ASSET_URL}")" "${PKG_ASSET_FILE}" || return 1

    mkdir -p "${INSTALLATION_PATH}/${PKG_DEST_NAME}/bin"
    chmod +x "${PKG_ASSET_FILE}"
    mv "${PKG_ASSET_FILE}" "${INSTALLATION_PATH}/${PKG_DEST_NAME}/bin/${PKG_NAME}"

    link_package "${PKG_DEST_NAME}" || return 1

    pkg_clean_tmpfiles
    pkg_finish
}

# Install a pre-built tarball: unpack it and move its contents into place.
# The discover stage must set PKG_VERSION, PKG_ASSET_URL, PKG_ASSET_FILE and
# PKG_ASSET_STEM (the top-level directory inside the archive).
install_prebuilt_package() {
    pkg_init "$1"
    load_spec "${PKG_FN}_spec" || return 1

    pkg_resolve_version
    case $? in 2) return 0 ;; 0) ;; *) return 1 ;; esac

    PKG_DEST_NAME=$(render "${PKG_PKGDIR}")
    download_url "${PKG_ASSET_URL}" "${PKG_ASSET_FILE}" || return 1

    echo "  → Extracting..."
    tar -xzf "${PKG_ASSET_FILE}" || return 1
    mkdir -p "${INSTALLATION_PATH}/${PKG_DEST_NAME}"
    mv "${PKG_ASSET_STEM}"/* "${INSTALLATION_PATH}/${PKG_DEST_NAME}/" || return 1

    link_package "${PKG_DEST_NAME}" || return 1

    rm -rf "${PKG_ASSET_STEM}" "${PKG_ASSET_FILE}"
    pkg_clean_tmpfiles
    pkg_finish
}

# Install via an upstream installer script. These are not versioned: the guard
# (a command or a directory) decides whether there is anything to do.
install_script_package() {
    pkg_init "$1"
    load_spec "${PKG_FN}_spec" || return 1

    pkg_banner

    if [[ -n "${PKG_GUARD_CMD}" ]] && command -v "${PKG_GUARD_CMD}" &>/dev/null; then
        echo "  ✓ ${PKG_TITLE} already installed$(pkg_version_suffix)"
        echo ""
        return 0
    fi
    if [[ -n "${PKG_GUARD_DIR}" && -d "${PKG_GUARD_DIR}" ]]; then
        echo "  ✓ ${PKG_TITLE} already installed"
        echo ""
        return 0
    fi

    cd "${_ORIGIN_PWD}/workdir" || return 1

    echo "  → Installing ${PKG_TITLE}..."
    download_url "${PKG_SCRIPT_URL}" "${PKG_SCRIPT_FILE}" || return 1
    "${PKG_SCRIPT_ENV[@]}" "${PKG_SCRIPT_RUNNER[@]}" "${PKG_SCRIPT_FILE}" \
        "${PKG_SCRIPT_ARGS[@]}" >/dev/null 2>&1
    rm -f "${PKG_SCRIPT_FILE}"

    run_optional_stage post_install

    echo "  ✓ Installed$(pkg_version_suffix)"
    echo ""
}

# ": <version>" when the package exposes a version command, else nothing.
pkg_version_suffix() {
    [[ -z "${PKG_VERSION_CMD}" ]] && return 0
    local out
    out=$(eval "${PKG_VERSION_CMD}" 2>/dev/null | head -n1)
    [[ -n "${out}" ]] && printf ': %s' "${out}"
    return 0
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

# Shared spec for every GNU FTP package: only the tag pattern differs.
pkg_gnu_spec() {
    PKG_LISTING_URL="${GNU_MIRROR}/${PKG_NAME}/"
    PKG_TAG_PATTERN="${PKG_NAME}-${GNU_VERSION_PATTERN[${PKG_NAME}]}"
    PKG_TARBALL_URL="${GNU_MIRROR}/${PKG_NAME}/"'${tag}.tar.gz'
    # Word splitting is intended: the table holds space-separated flags.
    PKG_CONFIGURE_FLAGS=(${GNU_CONFIGURE_FLAGS[${PKG_NAME}]:-})
}

pkg_openssl_spec() {
    PKG_TITLE="OpenSSL"
    PKG_LISTING_URL="https://github.com/openssl/openssl/tags"
    PKG_TAG_PATTERN='openssl-[0-9]+\.[0-9]+\.[0-9]+'
    PKG_TARBALL_URL='https://github.com/openssl/openssl/releases/download/${tag}/${tag}.tar.gz'
    # OpenSSL ships 'Configure', and splits the install into sw + ssldirs.
    PKG_CONFIGURE="Configure"
    PKG_CONFIGURE_FLAGS=(--openssldir="${_PREFIX}/ssl")
    PKG_INSTALL_TARGETS=(install_sw install_ssldirs)
}

pkg_openssl_post_install() {
    environment_prepend "CPATH"   "${_PREFIX}/include/openssl"
    environment_prepend "CXXPATH" "${_PREFIX}/include/openssl"
}

pkg_curl_spec() {
    PKG_TITLE="cURL"
    PKG_LISTING_URL="https://github.com/curl/curl/tags"
    # curl tags use underscores: curl-8_10_1
    PKG_TAG_PATTERN='curl-[0-9]+_[0-9]+_[0-9]+'
    PKG_TARBALL_URL='https://github.com/curl/curl/releases/download/${tag}/curl-${version}.tar.gz'
    PKG_TARBALL='curl-${version}.tar.gz'
    PKG_SRCDIR='curl-${version}'
    PKG_PKGDIR='curl-${version}'
    PKG_CONFIGURE_FLAGS=(--without-libpsl --with-openssl="${_PREFIX}")
}

pkg_curl_discover() {
    stage_discover || return 1
    PKG_VERSION="${PKG_VERSION//_/.}"
}

pkg_curl_post_install() {
    environment_prepend "CPATH"   "${_PREFIX}/include/curl"
    environment_prepend "CXXPATH" "${_PREFIX}/include/curl"
}

pkg_git_spec() {
    PKG_TITLE="Git"
    PKG_LISTING_URL="https://mirrors.edge.kernel.org/pub/software/scm/git/"
    PKG_TAG_PATTERN='git-[0-9]+\.[0-9]+\.[0-9]+'
    PKG_TARBALL_URL='https://mirrors.edge.kernel.org/pub/software/scm/git/git-${version}.tar.gz'
    # Git does not support a separate object directory.
    PKG_INTREE=1
}

pkg_ruby_spec() {
    PKG_TITLE="Ruby"
    PKG_LISTING_URL="https://cache.ruby-lang.org/pub/ruby/"
    PKG_TARBALL_URL='https://cache.ruby-lang.org/pub/ruby/${version%.*}/ruby-${version}.tar.gz'
    PKG_TARBALL='ruby-${version}.tar.gz'
    PKG_SRCDIR='ruby-${version}'
    PKG_PKGDIR='ruby-${version}'
    PKG_CONFIGURE_FLAGS=(
        --disable-install-doc
        --enable-load-relative
        --enable-devel
        --enable-shared
    )
}

# Ruby organises releases under per-minor-version subdirectories, so the newest
# patch release needs a second listing fetch.
pkg_ruby_discover() {
    local listing="ruby_listing.html"
    PKG_TMPFILES+=("${listing}")
    download_url "${PKG_LISTING_URL}" "${listing}" || return 1

    local major_minor_versions
    major_minor_versions=($(grep -oE '[0-9]+\.[0-9]+/' "${listing}" | sort -Vr | uniq))

    local ver patch_file
    for ver in "${major_minor_versions[@]}"; do
        download_url "${PKG_LISTING_URL}${ver}" "ruby_patch_listing.html" || continue
        patch_file=$(extract_version "ruby-${ver//\//}\.[0-9]+\.tar\.gz" "ruby_patch_listing.html")
        if [[ -n "${patch_file}" ]]; then
            PKG_VERSION=$(echo "${patch_file}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
            rm -f ruby_patch_listing.html
            break
        fi
        rm -f ruby_patch_listing.html
    done
    PKG_TAG="ruby-${PKG_VERSION}"
}

pkg_lua_spec() {
    PKG_TITLE="Lua"
    PKG_LISTING_URL="https://www.lua.org/ftp/"
    PKG_TAG_PATTERN='lua-[0-9]+\.[0-9]+\.[0-9]+'
    PKG_TARBALL_URL='https://www.lua.org/ftp/${tag}.tar.gz'
    PKG_INTREE=1
    # Lua has no configure script; the platform is a make target instead.
    PKG_CONFIGURE=""
    # INSTALL_TOP is rendered at build time, once the version is known.
    PKG_MAKE_VARS=(MYCFLAGS="-fPIC" 'INSTALL_TOP=${INSTALLATION_PATH}/${tag}')
    if [[ "${_OS}" == "macos" ]]; then
        PKG_MAKE_TARGETS=(macosx)
    else
        PKG_MAKE_TARGETS=(linux)
        PKG_MAKE_VARS+=(CFLAGS="${_CFLAGS}" CXXFLAGS="${_CXXFLAGS}" LDFLAGS="${_LDFLAGS}")
    fi
}

pkg_luarocks_spec() {
    PKG_TITLE="LuaRocks"
    PKG_LISTING_URL="https://luarocks.org/releases/"
    PKG_TAG_PATTERN='luarocks-[0-9]+\.[0-9]+\.[0-9]+'
    PKG_TARBALL_URL='https://luarocks.org/releases/${tag}.tar.gz'
    PKG_INTREE=1
}

pkg_jq_spec() {
    PKG_TITLE="jq"
    PKG_LISTING_URL="https://github.com/jqlang/jq/tags"
    PKG_TAG_PATTERN='jq-[0-9]+\.[0-9]+\.[0-9]+'
    PKG_ASSET='jq-${_OS}-${_ARCH}'
    PKG_ASSET_URL='https://github.com/jqlang/jq/releases/download/${tag}/${asset}'
}

pkg_neovim_spec() {
    PKG_TITLE="Neovim"
    PKG_PROBE_CMD="nvim"
    PKG_PKGDIR='nvim-${version}'
}

# Neovim publishes release assets only through the GitHub API.
pkg_neovim_discover() {
    local releases="nvim_releases.json"
    PKG_TMPFILES+=("${releases}")

    if ! command -v jq &>/dev/null; then
        echo "  ✗ jq is required but not installed"
        return 1
    fi

    download_url "https://api.github.com/repos/neovim/neovim/releases" "${releases}" || return 1

    PKG_VERSION=$(jq -r '.[].tag_name' "${releases}" \
        | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -Vr | head -n1)
    PKG_VERSION="${PKG_VERSION#v}"
    [[ -z "${PKG_VERSION}" ]] && return 1

    # Asset names look like nvim-linux-x86_64.tar.gz, nvim-macos-arm64.tar.gz
    PKG_ASSET_STEM=$(echo "nvim-${_OS}-${_ARCH}" | sed 's/amd/x86_/g')
    PKG_ASSET_FILE="${PKG_ASSET_STEM}.tar.gz"
    PKG_ASSET_URL=$(jq -r --arg ver "v${PKG_VERSION}" --arg name "${PKG_ASSET_FILE}" \
        '.[] | select(.tag_name == $ver) | .assets[] | select(.name == $name) | .browser_download_url' \
        "${releases}")

    if [[ -z "${PKG_ASSET_URL}" ]]; then
        echo "  ✗ Could not find download URL for ${PKG_ASSET_FILE}"
        return 1
    fi
}

pkg_neovim_post_install() {
    mkdir -p "${HOME}/.config/nvim/autoload"
}

pkg_nodejs_spec() {
    PKG_TITLE="Node.js"
    PKG_GUARD_CMD="node"
    PKG_VERSION_CMD="node --version"
    PKG_SCRIPT_URL="https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh"
}

pkg_nodejs_post_install() {
    export NVM_DIR="${HOME}/.nvm"
    [[ -s "${NVM_DIR}/nvm.sh" ]] && source "${NVM_DIR}/nvm.sh"

    echo "  → Installing Node.js LTS..."
    nvm install --lts >/dev/null 2>&1
    nvm use --lts >/dev/null 2>&1
}

pkg_rust_spec() {
    PKG_TITLE="Rust"
    PKG_GUARD_CMD="cargo"
    PKG_VERSION_CMD="rustc --version"
    PKG_SCRIPT_URL="https://sh.rustup.rs"
    PKG_SCRIPT_ARGS=(-y --no-modify-path)
}

pkg_rust_post_install() {
    source "${HOME}/.cargo/env"
}

pkg_uv_spec() {
    PKG_TITLE="uv (Python package manager)"
    PKG_GUARD_CMD="uv"
    PKG_SCRIPT_URL="https://astral.sh/uv/install.sh"
}

pkg_uv_post_install() {
    echo "  → Installing Python..."
    uv python install >/dev/null 2>&1 || true
}

pkg_oh_my_zsh_spec() {
    PKG_TITLE="Oh My Zsh"
    PKG_GUARD_DIR="${HOME}/.oh-my-zsh"
    PKG_SCRIPT_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
    PKG_SCRIPT_RUNNER=(zsh)
    PKG_SCRIPT_ARGS=(--unattended)
    # PKG_SCRIPT_ENV=(RUNZSH=no)
}

pkg_oh_my_zsh_post_install() {
    local custom_plugins="${HOME}/.oh-my-zsh/custom/plugins"
    echo "  → Installing plugins..."
    git clone https://github.com/zsh-users/zsh-autosuggestions --depth=1 \
        "${custom_plugins}/zsh-autosuggestions" >/dev/null 2>&1
    git clone https://github.com/zsh-users/zsh-syntax-highlighting --depth=1 \
        "${custom_plugins}/zsh-syntax-highlighting" >/dev/null 2>&1
}

pkg_starship_spec() {
    PKG_TITLE="Starship"
    PKG_GUARD_CMD="starship"
    PKG_VERSION_CMD="starship --version"
    PKG_SCRIPT_URL="https://starship.rs/install.sh"
    PKG_SCRIPT_RUNNER=(sh)
    PKG_SCRIPT_ARGS=(--bin-dir "${_PREFIX}/bin" -y)
}

pkg_starship_post_install() {
    echo "  → Downloading theme..."
    mkdir -p "${HOME}/.config/starship"
    download_url "https://starship.rs/presets/toml/jetpack.toml" \
        "${HOME}/.config/starship/jetpack.toml" || true
}

# ============================================================================
# Configuration
# ============================================================================

install_neovim_config() {
    hash -r
    echo "=== Setting up Neovim Configuration ==="
    if [[ -d "${HOME}/.config/nvim" && -f "${HOME}/.config/nvim/init.vim" ]]; then
        echo "  → Neovim configuration already exists. Skipping."
        echo ""
        return 0
    fi
    echo "  → Creating Neovim configuration..."
    mkdir -p "${HOME}/.config/nvim/autoload" || return 1
    cd "${HOME}/.config/nvim/" || return 1

    uv venv || true
    uv pip install neovim || true
    gem install neovim || true

    cat > "${HOME}/.config/nvim/init.vim" <<NVIM_CONFIG_EOF
source ~/.vimrc

set completeopt+=menuone,noselect,popup
let g:clipboard = 'osc52'
" Set Python 3 interpreter with system path; Not a virtual environment
set g:python3_host_prog  = '~/.config/nvim/.venv/bin/python3'
"
" If you are on macos or other POSIX system, or want to change the directory
" of python executable, need to change the path:
" let g:python3_host_prog  = '/opt/homebrew/bin/python3.14'

" let g:clang_library_path = '/usr/lib/llvm-20/lib/libclang.so'
" let g:node_host_prog = '~/.nvm/versions/node/*/bin/neovim-node-host'

source ~/.config/nvim/autoload/plug.vim
filetype off                  " required
call plug#begin()
Plug 'nvim-lua/plenary.nvim'
Plug 'OXY2DEV/markview.nvim'
Plug 'nvim-tree/nvim-tree.lua'
Plug 'nvim-tree/nvim-web-devicons'
Plug 'catppuccin/nvim'
Plug 'williamboman/mason.nvim'
Plug 'williamboman/mason-lspconfig.nvim'
Plug 'neovim/nvim-lspconfig'
Plug 'nvim-lualine/lualine.nvim'
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'nvim-telescope/telescope.nvim', { 'branch': '0.1.x' }
Plug 'preservim/tagbar'
Plug 'tpope/vim-fugitive'
Plug 'lewis6991/gitsigns.nvim'
Plug 'github/copilot.vim'
call plug#end()             " required
filetype plugin indent on   " required
syntax on
set termguicolors
colorscheme catppuccin-mocha

" lua scripts
lua << EOF
require('gitsigns').setup()
require('lualine').setup{ options = { theme = 'auto' } }

--- Nvim Tree
require('nvim-tree').setup {
  view = {
    width = 35,
    side = 'left',
    signcolumn = 'yes',
  },
  renderer = {
    highlight_git = true,
    indent_markers = { enable = true },
  },
  filters = {
    dotfiles = false,
  },
  actions = {
    open_file = { quit_on_open = false },
  }
}
vim.keymap.set('n', '<C-n>', ':NvimTreeToggle<CR>', { silent = true })

local presets = require('markview.presets');
require('markview').setup({
    markdown = {
        headings = presets.headings.slanted
    },
    preview = {
        icon_provider = 'devicons'
    }
})
EOF

lua << EOF
-- Setup lspconfig.
require('nvim-treesitter.configs').setup{
  ensure_installed = { 'c','cpp','python','cmake','make','bash','lua','json','powershell','vim','markdown' },
  highlight = { enable = true, additional_vim_regex_highlighting = false },
  indent = { enable = true },
}
EOF

lua << EOF
--- Setup LSP keymaps and settings based on server capabilities
vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('userLspConfigs', {}),
    callback = function(args)
        local client = assert(vim.lsp.get_client_by_id(args.data.client_id))

        vim.keymap.set('n', '<leader>gd',       vim.lsp.buf.declaration,     {silent=true})
        vim.keymap.set('n', '<leader>gD',       vim.lsp.buf.definition,      {silent=true})
        vim.keymap.set('n', '<leader>gi',       vim.lsp.buf.implementation,  {silent=true})
        vim.keymap.set('n', '<leader>gr',       vim.lsp.buf.references,      {silent=true})
        vim.keymap.set('n', '<leader>g0',       vim.lsp.buf.document_symbol, {silent=true})
        vim.keymap.set('n', '<leader><leader>', vim.lsp.buf.hover,           {silent=true})
        vim.keymap.set('n', '<leader>tD',       vim.lsp.buf.type_definition, {silent=true})

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'typeHierARCHyProvider') then
            vim.keymap.set('n', '<leader>tP', function() vim.lsp.buf.typehierachy({kind='subtypes'})   end, {silent=true})
            vim.keymap.set('n', '<leader>tC', function() vim.lsp.buf.typehierachy({kind='supertypes'}) end, {silent=true})
        end

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'codeLensProvider') then
            vim.keymap.set('n', '<leader>lc', function() vim.lsp.codelens.clear  ({bufnr=0, client_id=args.data.client_id}) end, {silent=true})
            vim.keymap.set('n', '<leader>ls', function() vim.lsp.codelens.display({bufnr=0, client_id=args.data.client_id}) end, {silent=true})
            vim.nvim_create_autocmd({'BufEnter','CursorHold','InsertLeave'}, {
                buffer = args.buf,
                group = vim.api.nvim_create_augroup('userLspConfigs', {clear=false}),
                callback = function() vim.lsp.codelens.refresh({ bufnr = 0 }) end
            })
            vim.keymap.set('n', '<leader>lr', function() vim.lsp.codelens.refresh({bufnr=0, client_id=args.data.client_id}) end, {silent=true})
            vim.keymap.set('n', '<leader>lS', function() vim.lsp.codelens.save   ({bufnr=0, client_id=args.data.client_id}) end, {silent=true})
            vim.keymap.set('n', '<leader>lg', function() vim.lsp.codelens.get({bufnr=0}) end, {silent=true})
            vim.keymap.set('n', '<leader>lR', vim.lsp.codelens.run, {silent=true})
        end

        vim.diagnostic.config({
            virtual_text = {
                prefix = '●',
                spacing = 4,
            },
            float = {
                border = 'rounded',
                source = 'always',
                header = '',
                prefix = '',
            },
            signs = true,
            underline = true,
            update_in_insert = false,
            severity_sort = true,
        })
        vim.keymap.set('n', '<leader>ee',  vim.diagnostic.open_float,               {silent=true})
        vim.keymap.set('n', '<leader>e]', function() vim.diagnostic.jump({count =  1, float=true}) end, {silent=true})
        vim.keymap.set('n', '<leader>e[', function() vim.diagnostic.jump({count = -1, float=true}) end, {silent=true})
        vim.keymap.set('n', '<leader>el', function() vim.diagnostic.setqflist(); vim.cmd('copen') end,  {silent=true})

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'signatureHelpProvider') then
            vim.keymap.set('n', '<leader>hS',    vim.lsp.buf.signature_help, {silent=true})
        end

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'codeActionProvider') then
            vim.keymap.set('n', '<leader>hA',    vim.lsp.buf.code_action,    {silent=true})
        end

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'renameProvider') then
            vim.keymap.set('n', '<F2>',          vim.lsp.buf.rename,         {silent=true})
        end

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'WorkspaceSymbolOptions') then
            vim.keymap.set('n', '<leader>G0',    vim.lsp.buf.workspace_symbol,{silent=true})
        end

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'inlayHintProvider') then
            vim.lsp.inlay_hint.enable(true)
        end

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'completionProvider') then
            buffer = vim.api.nvim_get_current_buf(),
            vim.lsp.completion.enable(true, client.id, 0, {
                autotrigger = true,
                convert = function(item)
                    return { abbr = item.label:gsub('%b()', '') }
                end,
            })
        end

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'documentFormattingProvider') then
            vim.keymap.set('n', '<leader>hA', function()
                    vim.lsp.buf.format({ bufnr = args.buf, id = client.id, timeout_ms = 1000 })
                end
                ,{silent=true})
            vim.api.nvim_create_autocmd('BufWritePre', {
                group = vim.api.nvim_create_augroup('userLspConfigs', {clear=false}),
                buffer = args.buf,
                callback = function()
                    vim.lsp.buf.format({ bufnr = args.buf, id = client.id, timeout_ms = 1000 })
                end,
            })
        end

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'documentHighlightProvider') then
            vim.api.nvim_create_autocmd('CursorHold', {
                buffer = args.buf,
                group = vim.api.nvim_create_augroup('userLspConfigs', {clear=false}),
                callback = function() vim.lsp.buf.document_highlight() end
            })
            vim.api.nvim_create_autocmd('CursorHoldI', {
                buffer = args.buf,
                group = vim.api.nvim_create_augroup('userLspConfigs', {clear=false}),
                callback = function() vim.lsp.buf.document_highlight() end
            })
            vim.api.nvim_create_autocmd('CursorMoved', {
                buffer = args.buf,
                group = vim.api.nvim_create_augroup('userLspConfigs', {clear=false}),
                callback = function() vim.lsp.buf.clear_references() end
            })
        end
    end,
})

--- Mason
require('mason').setup()
require('mason-lspconfig').setup({
    ensure_installed = { 'clangd', 'pyright', 'bashls', 'lua_ls', 'jsonls', 'powershell_es', 'vimls', 'markdown_oxide'},
    automatic_enable = true
})
EOF

" == Telescope ==
nnoremap <silent> <leader>ff :Telescope find_files<CR>
nnoremap <silent> <leader>fg :Telescope live_grep<CR>
nnoremap <silent> <leader>fb :Telescope buffers<CR>
nnoremap <silent> <leader>fh :Telescope help_tags<CR>
nnoremap <silent> <leader>Ch :highlight clear<CR>

" === Tagbar ===
nnoremap <leader>tb :TagbarToggle<CR>
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#formatter = 'default'

" CUDA filetype settings
augroup cuda_ft
  autocmd!
  autocmd BufRead,BufNewFile *.cu,*.cuh set filetype=cuda
augroup END

" Markdown filetype settings
augroup markdown
  autocmd!
  autocmd BufRead,BufNewFile *.md setlocal filetype=markdown
augroup END
NVIM_CONFIG_EOF
    echo "  ✓ Neovim configuration created"
    echo "  → Creating Vim configuration..."
    cat > "${HOME}/.vimrc" <<EOF
set hlsearch
set encoding=utf8
set fileencodings=utf-8,euc-kr,cp949
set bs=indent,eol,start
set history=1000
set ruler
set nobackup
set title
set showmatch
set nowrap
set wmnu
set wildmenu
set wildmode=longest:full,full
set cursorline
set tabstop=4
set shiftwidth=4
set softtabstop=4
set expandtab
set clipboard+=unnamedplus
set nu
set nocompatible
EOF
    echo "  ✓ Vim configuration created"
    echo ""
    echo "  → Installing vim-plug..."
    download_url "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" \
        "${HOME}/.config/nvim/autoload/plug.vim" || true

    echo "  → Installing plugins..."
    nvim +PlugInstall +qall >/dev/null 2>&1 || true
    echo "  ✓ Installed"
    echo ""
}

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
    #install_pkg "bison"
    #install_pkg "m4"
    #install_pkg "texinfo"
    #install_pkg "make"
    #install_pkg "binutils"
    #install_pkg "glibc"
    #install_pkg "coreutils"
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
