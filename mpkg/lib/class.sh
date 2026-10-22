# mpkg / lib/class.sh — single inheritance for package scripts.
#
# Bash has no classes, so mpkg builds one by sourcing scripts in layers.
# A package script starts with `mpkg_inherit <base>`; the base is sourced
# first, then the package body overrides whichever methods it cares about.
#
# After each layer is sourced it is "sealed": every method the layer defined is
# copied to a level-tagged name (mpkg_L<n>_<method>) and replaced by a
# dispatcher. The dispatcher always runs the most-derived implementation, and
# `mpkg_super <method>` runs the nearest implementation *below* the one
# currently executing — so a layer can extend its base instead of replacing it.
#
#   packages/curl.sh
#       mpkg_inherit srccommon          # srccommon inherits pkgcommon
#       mpkg_discover() {
#           mpkg_super discover || return 1
#           MPKG_VERSION="${MPKG_VERSION//_/.}"
#       }

MPKG_METHODS=(
    run describe env discover fetch prepare configure build install
    link cleanup post_install verify remove
)

declare -A MPKG_IMPL=()
MPKG_LEVEL=0
MPKG_LOADED=" "

# --- inheritance ------------------------------------------------------------

mpkg_inherit() {
    local base="$1" file
    file="${MPKG_PACKAGES}/${base}.sh"
    [[ "${MPKG_LOADED}" == *" ${base} "* ]] && return 0
    [[ -r "${file}" ]] || { mpkg::err "unknown base class '${base}'"; return 1; }
    MPKG_LOADED+="${base} "
    # shellcheck source=/dev/null
    . "${file}" || return 1
    mpkg::class_seal
}

mpkg::class_seal() {
    local lvl=$(( ++MPKG_LEVEL )) m body
    for m in "${MPKG_METHODS[@]}"; do
        declare -F "mpkg_${m}" >/dev/null 2>&1 || continue
        body="$(declare -f "mpkg_${m}")"
        # Already a dispatcher: this layer did not override the method.
        [[ "${body}" == *"mpkg::dispatch"* ]] && continue
        eval "mpkg_L${lvl}_${m}() ${body#*$'\n'}" || return 1
        MPKG_IMPL[$m]="${MPKG_IMPL[$m]:-}${lvl} "
        eval "mpkg_${m}() { mpkg::dispatch ${m} \"\$@\"; }"
    done
}

mpkg::dispatch() {
    local m="$1"; shift
    local levels="${MPKG_IMPL[$m]:-}"
    [[ -z "${levels}" ]] && { mpkg::err "package '${MPKG_NAME}' has no '${m}' stage"; return 1; }
    levels="${levels% }"
    local MPKG_LVL="${levels##* }"
    "mpkg_L${MPKG_LVL}_${m}" "$@"
}

# Call the implementation one layer below the caller's.
mpkg_super() {
    local m="$1"; shift
    local l best=""
    for l in ${MPKG_IMPL[$m]:-}; do
        (( l < ${MPKG_LVL:-9999} )) && best="$l"
    done
    [[ -z "${best}" ]] && { mpkg::err "mpkg_super ${m}: no base implementation"; return 1; }
    local MPKG_LVL="${best}"
    "mpkg_L${best}_${m}" "$@"
}

# Does the class implement <method> at all?
mpkg_has() { [[ -n "${MPKG_IMPL[$1]:-}" ]]; }

# Run <method> when present; never fails the install.
mpkg::optional() {
    mpkg_has "$1" || return 0
    mpkg::dispatch "$@"
    return 0
}

# Same, but the method's exit status is propagated. Used for mpkg_verify, where
# "the build finished but the result is unusable" has to be a failure.
mpkg::optional_strict() {
    mpkg_has "$1" || return 0
    mpkg::dispatch "$@"
}

# --- field defaults ---------------------------------------------------------

mpkg::fields_reset() {
    MPKG_NAME="$1"
    MPKG_KIND=""
    MPKG_TITLE="${MPKG_NAME}"
    MPKG_DESC=""
    MPKG_HOMEPAGE=""
    MPKG_DEPENDS=()
    MPKG_OPTDEPENDS=()
    # System tools that must already exist; mpkg checks but never installs them.
    MPKG_REQUIRES_CMD=()

    # Version discovery / probing.
    MPKG_PROBE_CMD="${MPKG_NAME}"
    MPKG_VERSION_CMD=""
    MPKG_TAG=""
    MPKG_VERSION=""
    MPKG_INSTALLED_VERSION="0.0.0"
    MPKG_UNVERSIONED=0
    MPKG_TMPFILES=()

    # Where releases live and what the artifact is called.
    MPKG_LISTING_URL=""
    # Alternative to a listing: "owner/repo", whose latest release is taken.
    MPKG_GITHUB_REPO=""
    MPKG_TAG_PATTERN=""
    MPKG_TAG_CANDIDATES=5
    MPKG_TARBALL_URL=""
    # Probed with a HEAD request during discovery to reject tags that have no
    # published artifact (release candidates, doc-only tags). Defaults to the
    # tarball, then the asset URL.
    MPKG_VERIFY_URL=""
    MPKG_TARBALL='${tag}.tar.gz'
    MPKG_SRCDIR='${tag}'
    MPKG_DESTDIR='${tag}'
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

    # Pre-built artifacts.
    MPKG_ASSET=""
    MPKG_ASSET_URL=""
    MPKG_ASSET_FILE=""
    MPKG_ASSET_STEM=""
    # Executables to pick out of a release archive (ghcommon); default: the
    # probe command.
    MPKG_BINARIES=()

    # Upstream installer scripts.
    MPKG_GUARD_CMD=""
    MPKG_GUARD_DIR=""
    MPKG_SCRIPT_URL=""
    MPKG_SCRIPT_FILE="install_${MPKG_NAME//-/_}.sh"
    MPKG_SCRIPT_RUNNER=(bash)
    MPKG_SCRIPT_ARGS=()
    MPKG_SCRIPT_ENV=()
}

# Tear the previous class down so nothing leaks into the next package.
mpkg::class_reset() {
    local m l
    for m in "${MPKG_METHODS[@]}"; do
        for l in ${MPKG_IMPL[$m]:-}; do
            unset -f "mpkg_L${l}_${m}" 2>/dev/null
        done
        unset -f "mpkg_${m}" 2>/dev/null
        MPKG_IMPL[$m]=""
    done
    MPKG_LEVEL=0
    MPKG_LOADED=" "
    mpkg::fields_reset "$1"
}

# Build the class for <name>: reset, source packages/<name>.sh, seal the body.
mpkg::class_load() {
    local name="$1" file
    file="${MPKG_PACKAGES}/${name}.sh"
    [[ -r "${file}" ]] || { mpkg::err "no such package: ${name}"; return 1; }
    mpkg::class_reset "${name}"
    # shellcheck source=/dev/null
    . "${file}" || { mpkg::err "failed to load package script ${file}"; return 1; }
    mpkg::class_seal
    mpkg::optional describe
}
