mpkg_init_env() {
    MPKG_TMPDIR="${MPKG_TMPDIR:-$(mktemp -d)}"
    MPKG_PREFIX="${MPKG_PREFIX:-$HOME/.local}"
    MPKG_DB_DIR="${MPKG_DB_DIR:-$HOME/.local/mpkg.db}"
    MPKG_VENV_DIR="${MPKG_VENV_DIR:-$HOME/.local/venvs}"

    if [ ! -f "$MPKG_DB_DIR" ]; then
        sqlite3 "$MPKG_DB_DIR" \
            "CREATE TABLE IF NOT EXISTS package_info (name TEXT PRIMARY KEY, version TEXT, PROBE);"
    fi
}

mpkg_download_url() {
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

mpkg_extract_version() {
    local pattern="$1"
    local file="$2"
    grep -oE "$pattern" "$file" | sort -Vr | head -n1
}

mpkg_link_package() {
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

mpkg_unlink_package() {
    local package_name="$1"
    local pkg_path="${INSTALLATION_PATH}/${package_name}"
    while IFS= read -r -d '' file; do
        local relative_path="${file#${pkg_path}/}"
        local target="${_PREFIX}/${relative_path}"
        [ -L "${target}" ] && rm -f "${target}"
    done < <(find "${pkg_path}" -type f -print0 | sort -z)
}


mpkg_init_install_info() {
    MPKG_NAME="$1"
    MPKG_FN="pkg_${MPKG_NAME//-/_}"

    MPKG_TITLE="${MPKG_NAME}"
    MPKG_PROBE_CMD="${MPKG_NAME}"
    MPKG_TAG=""
    MPKG_VERSION=""
    MPKG_INSTALLED_VERSION="0.0.0"
    MPKG_TMPFILES=()

    # Where to look for releases, and what the artifact is called.
    MPKG_LISTING_URL=""
    MPKG_TAG_PATTERN=""
    MPKG_TARBALL_URL=""
    MPKG_TARBALL='${tag}.tar.gz'
    MPKG_SRCDIR='${tag}'
    MPKG_MPKGDIR='${tag}'
    MPKG_TARBALL_FILE=""
    MPKG_SRC_DIR=""
    MPKG_DEST_NAME=""

    # How to build it.
    MPKG_INTREE=0
    MPKG_CONFIGURE="configure"
    MPKG_CONFIGURE_FLAGS=()
    MPKG_MAKE_TARGETS=()
    MPKG_MAKE_VARS=()
    MPKG_INSTALL_TARGETS=(install)

    # Pre-built artifacts (binary / prebuilt kinds).
    MPKG_ASSET=""
    MPKG_ASSET_URL=""
    MPKG_ASSET_FILE=""
    MPKG_ASSET_STEM=""

    # Upstream installer scripts (script kind).
    MPKG_GUARD_CMD=""
    MPKG_GUARD_DIR=""
    MPKG_VERSION_CMD=""
    MPKG_SCRIPT_URL=""
    MPKG_SCRIPT_FILE="install_${MPKG_NAME//-/_}.sh"
    MPKG_SCRIPT_RUNNER=(bash)
    MPKG_SCRIPT_ARGS=()
    MPKG_SCRIPT_ENV=()
}
