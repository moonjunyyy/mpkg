# Go, the newest stable release from go.dev, checked against the published
# SHA-256 before it is unpacked.
#
# A Go distribution is one self-contained tree (GOROOT) that the go command
# finds from its own real location, so nothing has to set GOROOT. The tree
# goes into the package's private .mpkg/goroot, which is not linked into the
# prefix (it is ~15000 files nothing else reads); bin/ carries go and gofmt as
# links into it. What `go install` builds lands in $(go env GOPATH)/bin,
# ~/go/bin by default, which env.sh puts on PATH.

mpkg_inherit tarcommon

MPKG_TITLE="Go"
MPKG_DESC="The Go toolchain: go, gofmt"
MPKG_HOMEPAGE="https://go.dev/"
MPKG_PROBE_CMD="go"
MPKG_DEPENDS=(jq)
MPKG_DESTDIR='go-${version}'

mpkg_discover() {
    local releases="go-releases.json" row
    MPKG_TMPFILES+=("${releases}")
    command -v jq >/dev/null 2>&1 || { mpkg::err "jq is required to read the Go release list"; return 1; }
    mpkg::download "https://go.dev/dl/?mode=json" "${releases}" || return 1

    # Newest first; only stable releases are listed without &include=all.
    row="$(jq -r --arg os "${_GOOS}" --arg arch "${_ARCH}" '
        [.[] | select(.stable)][0] as $r
        | $r.files[] | select(.os == $os and .arch == $arch and .kind == "archive")
        | [$r.version, .filename, .sha256] | @tsv' "${releases}" | head -n1)"
    [[ -n "${row}" ]] || { mpkg::err "go: no stable release for ${_GOOS}/${_ARCH}"; return 1; }
    IFS=$'\t' read -r MPKG_TAG MPKG_ASSET_FILE MPKG_GO_SHA256 <<< "${row}"

    MPKG_VERSION="${MPKG_TAG#go}"
    MPKG_ASSET_URL="https://go.dev/dl/${MPKG_ASSET_FILE}"
    MPKG_ASSET_STEM="go"
}

mpkg_fetch() {
    MPKG_DEST_NAME="$(mpkg::render "${MPKG_DESTDIR}")"
    MPKG_TMPFILES+=("${MPKG_ASSET_FILE}" "${MPKG_ASSET_STEM}")
    rm -rf "${MPKG_ASSET_STEM}"
    mpkg::download "${MPKG_ASSET_URL}" "${MPKG_ASSET_FILE}" || return 1

    local sum=""
    if command -v sha256sum >/dev/null 2>&1; then sum="$(sha256sum "${MPKG_ASSET_FILE}")"
    elif command -v shasum >/dev/null 2>&1;  then sum="$(shasum -a 256 "${MPKG_ASSET_FILE}")"
    fi
    sum="${sum%% *}"
    if [[ -z "${sum}" ]]; then
        mpkg::warn "go: no sha256sum or shasum; the archive is not verified"
    elif [[ "${sum}" != "${MPKG_GO_SHA256}" ]]; then
        mpkg::err "go: ${MPKG_ASSET_FILE} does not match its published SHA-256"
        mpkg::err "  expected ${MPKG_GO_SHA256}"
        mpkg::err "  got      ${sum}"
        return 1
    else
        mpkg::step "checksum verified"
    fi

    mpkg::step "extracting ${MPKG_ASSET_FILE}"
    mpkg::run tar -xf "${MPKG_ASSET_FILE}" \
        || mpkg::stage_failed "go: could not extract ${MPKG_ASSET_FILE}"
}

mpkg_install() {
    local dest="${MPKG_SOFT}/${MPKG_DEST_NAME}" b
    [[ -x "${MPKG_ASSET_STEM}/bin/go" ]] || { mpkg::err "archive did not contain go/bin/go"; return 1; }
    rm -rf "${dest}"
    mkdir -p "${dest}/bin" "${dest}/.mpkg" || return 1
    cp -a "${MPKG_ASSET_STEM}" "${dest}/.mpkg/goroot" || return 1
    for b in "${dest}"/.mpkg/goroot/bin/*; do
        ln -s "../.mpkg/goroot/bin/${b##*/}" "${dest}/bin/${b##*/}" || return 1
    done
    mpkg::step "installed into ${dest}"
}

# Tools later packages install with `go install` (gopls for mason) go here.
mpkg_env() {
    environment_prepend "PATH" "${GOBIN:-${GOPATH:-${HOME}/go}/bin}"
    return 0
}

mpkg_verify() {
    local out
    out="$("${MPKG_SOFT}/${MPKG_DEST_NAME}/bin/go" version 2>&1)" \
        || { mpkg::err "the new go does not run: ${out}"; return 1; }
    [[ "${out}" == *"${MPKG_TAG}"* ]] \
        || { mpkg::err "unexpected 'go version' output: ${out}"; return 1; }
}
