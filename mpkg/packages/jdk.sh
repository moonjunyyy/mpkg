# Eclipse Temurin, the most recent LTS release, from the Adoptium API.
#
# A JDK is a self-contained tree that finds its own lib/ relative to the
# launcher, so it goes whole into libexec/jdk/ -- linking its lib/ into the
# prefix would put libjvm and friends on everybody's library path. bin/ only
# carries links to the launchers, and JAVA_HOME is ${MPKG_PREFIX}/libexec/jdk.

mpkg_inherit tarcommon

MPKG_TITLE="JDK"
MPKG_DESC="Java development kit (Eclipse Temurin LTS): java, javac, jar"
MPKG_HOMEPAGE="https://adoptium.net/"
MPKG_PROBE_CMD="javac"
MPKG_DEPENDS=(jq)
MPKG_DESTDIR='jdk-${version}'

MPKG_ADOPTIUM_API="https://api.adoptium.net/v3"

mpkg_discover() {
    local info="jdk-releases.json" asset="jdk-asset.json" lts os arch
    MPKG_TMPFILES+=("${info}" "${asset}")
    command -v jq >/dev/null 2>&1 || { mpkg::err "jq is required to query the Adoptium API"; return 1; }

    mpkg::download "${MPKG_ADOPTIUM_API}/info/available_releases" "${info}" || return 1
    lts="$(jq -r '.most_recent_lts // empty' "${info}")"
    [[ -n "${lts}" ]] || { mpkg::err "jdk: Adoptium reported no LTS release"; return 1; }

    os="${_OS/macos/mac}"
    arch="${_ARCH/amd64/x64}"; arch="${arch/arm64/aarch64}"
    mpkg::download "${MPKG_ADOPTIUM_API}/assets/latest/${lts}/hotspot?os=${os}&architecture=${arch}&image_type=jdk&vendor=eclipse" \
        "${asset}" || return 1

    # release_name is both the tag (jdk-25.0.1+8) and the archive's top directory.
    MPKG_TAG="$(jq -r '.[0].release_name // empty' "${asset}")"
    MPKG_ASSET_URL="$(jq -r '.[0].binary.package.link // empty' "${asset}")"
    MPKG_ASSET_FILE="$(jq -r '.[0].binary.package.name // empty' "${asset}")"
    [[ -n "${MPKG_TAG}" && -n "${MPKG_ASSET_URL}" && -n "${MPKG_ASSET_FILE}" ]] \
        || { mpkg::err "jdk: no Temurin ${lts} build for ${os}/${arch}"; return 1; }
    MPKG_VERSION="${MPKG_TAG#jdk-}"
    MPKG_ASSET_STEM="${MPKG_TAG}"
}

mpkg_install() {
    local dest="${MPKG_SOFT}/${MPKG_DEST_NAME}" home b
    home="${MPKG_ASSET_STEM}"
    # macOS builds are bundles: jdk-25+8/Contents/Home is the actual JDK.
    [[ -d "${home}/Contents/Home" ]] && home="${home}/Contents/Home"
    [[ -x "${home}/bin/javac" ]] || { mpkg::err "archive did not contain ${home}/bin/javac"; return 1; }

    rm -rf "${dest}"
    mkdir -p "${dest}/bin" "${dest}/libexec" || return 1
    cp -a "${home}" "${dest}/libexec/jdk" || return 1
    for b in "${dest}"/libexec/jdk/bin/*; do
        ln -s "../libexec/jdk/bin/${b##*/}" "${dest}/bin/${b##*/}" || return 1
    done
    [[ -d "${home}/man" ]] && { mkdir -p "${dest}/share" && cp -a "${home}/man" "${dest}/share/man" || return 1; }
    mpkg::step "installed into ${dest}"
}

mpkg_env() {
    [[ -x "${MPKG_PREFIX}/libexec/jdk/bin/java" ]] && export JAVA_HOME="${MPKG_PREFIX}/libexec/jdk"
    return 0
}

mpkg_verify() {
    "${MPKG_SOFT}/${MPKG_DEST_NAME}/bin/javac" -version >/dev/null 2>&1 && return 0
    mpkg::err "the new javac does not run"
    return 1
}
