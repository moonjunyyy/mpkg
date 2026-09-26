mpkg_inherit tarcommon

MPKG_TITLE="Neovim"
MPKG_DESC="Hyperextensible Vim-based text editor"
MPKG_HOMEPAGE="https://neovim.io/"
MPKG_PROBE_CMD="nvim"
MPKG_DESTDIR='nvim-${version}'
MPKG_DEPENDS=(jq)

# Neovim publishes its release assets only through the GitHub API.
mpkg_discover() {
    local releases="nvim-releases.json"
    MPKG_TMPFILES+=("${releases}")

    command -v jq >/dev/null 2>&1 || { mpkg::err "jq is required to query the Neovim releases API"; return 1; }
    mpkg::download "https://api.github.com/repos/neovim/neovim/releases" "${releases}" || return 1

    MPKG_VERSION="$(jq -r '.[].tag_name' "${releases}" \
        | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -Vr | head -n1)"
    MPKG_VERSION="${MPKG_VERSION#v}"
    [[ -n "${MPKG_VERSION}" ]] || { mpkg::err "no stable Neovim release found"; return 1; }
    MPKG_TAG="v${MPKG_VERSION}"

    # Assets are named nvim-linux-x86_64.tar.gz / nvim-macos-arm64.tar.gz
    MPKG_ASSET_STEM="$(printf 'nvim-%s-%s' "${_OS}" "${_ARCH}" | sed 's/amd/x86_/')"
    MPKG_ASSET_FILE="${MPKG_ASSET_STEM}.tar.gz"
    MPKG_ASSET_URL="$(jq -r --arg ver "v${MPKG_VERSION}" --arg name "${MPKG_ASSET_FILE}" \
        '.[] | select(.tag_name == $ver) | .assets[] | select(.name == $name) | .browser_download_url' \
        "${releases}")"

    [[ -n "${MPKG_ASSET_URL}" ]] \
        || { mpkg::err "no Neovim asset named ${MPKG_ASSET_FILE} in release v${MPKG_VERSION}"; return 1; }
}
