# mpkg / lib/util.sh — downloads, version discovery, template rendering.

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

# Pick a downloader once. Prefer a curl that actually works over a freshly
# built one that may not have a CA bundle yet.
mpkg::fetcher() {
    if command -v curl >/dev/null 2>&1; then echo curl
    elif command -v wget >/dev/null 2>&1; then echo wget
    else echo ""
    fi
}

mpkg::download() {
    local url="$1" output="$2" tool
    tool="$(mpkg::fetcher)"
    mpkg::step "downloading $(basename "${output}")"
    mpkg::dbg "from ${url}"
    case "${tool}" in
        curl) mpkg::run curl -fsSL --retry 3 --retry-delay 1 -o "${output}" "${url}" ;;
        wget) mpkg::run wget -q --tries=3 -O "${output}" "${url}" ;;
        *)    mpkg::err "neither curl nor wget is available"; return 1 ;;
    esac || { mpkg::err "download failed: ${url}"; rm -f "${output}"; return 1; }
}

# Backwards-compatible name used by the package scripts.
download_url() { mpkg::download "$@"; }

# True when a URL is reachable. Used to skip release candidates and other
# tags that have no matching tarball.
mpkg::url_exists() {
    local url="$1" tool
    tool="$(mpkg::fetcher)"
    case "${tool}" in
        curl) curl -fsSL -I --retry 1 -o /dev/null "${url}" >/dev/null 2>&1 ;;
        wget) wget -q --spider --tries=1 "${url}" >/dev/null 2>&1 ;;
        *)    return 0 ;;
    esac
}

# The tag of a GitHub repository's latest release, read from the redirect of
# /releases/latest. No API call, so no rate limit; pre-releases are excluded.
mpkg::github_latest_tag() {
    local repo="$1" url
    case "$(mpkg::fetcher)" in
        curl) url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
                        "https://github.com/${repo}/releases/latest" 2>/dev/null)" ;;
        wget) url="$(wget -S --spider "https://github.com/${repo}/releases/latest" 2>&1 \
                        | awk '/^ *Location: /{l=$2} END{print l}')" ;;
    esac
    [[ "${url}" == */releases/tag/* ]] || return 1
    printf '%s' "${url##*/releases/tag/}"
}

# ---------------------------------------------------------------------------
# Versions
# ---------------------------------------------------------------------------

# All matches of <pattern> in <file>, newest first, deduplicated.
mpkg::match_versions() {
    local pattern="$1" file="$2"
    grep -oE "${pattern}" "${file}" | sort -Vru
}

# Single newest match. Kept for package scripts that only need one.
extract_version() {
    mpkg::match_versions "$1" "$2" | head -n1
}

# Strip an archive suffix from a tag: git-2.55.0.tar.gz -> git-2.55.0
mpkg::trim_tag() {
    printf '%s' "${1%%.tar.*}"
}

# Numeric dotted-version comparison. Echoes -1, 0 or 1 for a<b, a==b, a>b.
mpkg::vercmp() {
    local a="$1" b="$2"
    [[ "$a" == "$b" ]] && { echo 0; return; }
    local newest
    newest=$(printf '%s\n%s\n' "$a" "$b" | sort -Vr | head -n1)
    [[ "${newest}" == "$a" ]] && echo 1 || echo -1
}

# Probe an installed command for its version; 0.0.0 when absent.
mpkg::probe_version() {
    local cmd="$1" out
    command -v "${cmd}" >/dev/null 2>&1 || { echo "0.0.0"; return; }
    out=$( { "${cmd}" --version 2>/dev/null || "${cmd}" -v 2>/dev/null || true; } \
           | tr '[:upper:]' '[:lower:]' | head -n5 )
    if [[ "${out}" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then echo "${BASH_REMATCH[1]}"
    elif [[ "${out}" =~ ([0-9]+\.[0-9]+) ]];        then echo "${BASH_REMATCH[1]}"
    else echo "0.0.0"
    fi
}
get_installed_version() { mpkg::probe_version "$@"; }

# ---------------------------------------------------------------------------
# Templates
# ---------------------------------------------------------------------------

# Expand a single-quoted spec template once the version is known.
# Placeholders: ${name} ${tag} ${version} ${asset} plus any exported variable
# (${_OS}, ${_ARCH}, ${MPKG_PREFIX}, ...).
mpkg::render() {
    local name="${MPKG_NAME}" tag="${MPKG_TAG}" version="${MPKG_VERSION}" \
          asset="${MPKG_ASSET_FILE:-}"
    eval "printf '%s' \"$1\""
}
render() { mpkg::render "$@"; }

# ---------------------------------------------------------------------------
# Filesystem
# ---------------------------------------------------------------------------

# Is <name> linkable as a shared library from the prefix? (-l<name> resolves)
mpkg::have_shared_lib() {
    local name="$1" d
    for d in "${MPKG_PREFIX}/lib" "${MPKG_PREFIX}/lib64"; do
        [[ -e "${d}/lib${name}.so" || -e "${d}/lib${name}.dylib" ]] && return 0
    done
    return 1
}

# tree_digest <dir> — a short content hash of the regular files under <dir>,
# names included, so it changes whenever a file is added, removed, renamed or
# edited. MPKG_DIGEST_SKIP lists paths, relative to <dir>, to leave out.
mpkg::tree_digest() {
    local dir="$1"
    local sum=(cksum)
    if command -v sha256sum >/dev/null 2>&1; then sum=(sha256sum)
    elif command -v shasum >/dev/null 2>&1; then sum=(shasum -a 256)
    fi
    (
        cd "${dir}" || exit 1
        find . -type f -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
            f="${f#./}"
            [[ " ${MPKG_DIGEST_SKIP:-} " == *" ${f} "* ]] && continue
            printf '%s\n' "${f}"; cat "${f}"
        done
    ) | "${sum[@]}" | cut -c1-10
}

mpkg::confirm() {
    [[ ${MPKG_ASSUME_YES:-0} -eq 1 ]] && return 0
    local reply
    printf '%s [y/N] ' "$1"
    read -r reply || return 1
    [[ "${reply}" =~ ^[Yy] ]]
}
