# mpkg / lib/core.sh — platform detection, prefix layout, logging, build env.
# Sourced by the `mpkg` CLI. Defines only functions and globals.

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------

mpkg::detect_os() {
    case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
        darwin) echo "macos" ;;
        linux)  echo "linux" ;;
        *)      uname -s | tr '[:upper:]' '[:lower:]' ;;
    esac
}

mpkg::detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *)             uname -m ;;
    esac
}

mpkg::detect_jobs() {
    if [[ "${_OS}" == "macos" ]]; then
        sysctl -n hw.ncpu 2>/dev/null || echo 1
    else
        nproc 2>/dev/null || echo 1
    fi
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

MPKG_VERBOSE=0
MPKG_QUIET=0
MPKG_LOG=""

mpkg::colors() {
    if [[ -t 1 && "${NO_COLOR:-}" == "" ]]; then
        C_RST=$'\033[0m'; C_B=$'\033[1m'; C_DIM=$'\033[2m'
        C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_BLU=$'\033[34m'
    else
        C_RST=""; C_B=""; C_DIM=""; C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""
    fi
}

mpkg::say()  { [[ ${MPKG_QUIET} -eq 1 ]] || printf '%s\n' "$*"; }
mpkg::head() { [[ ${MPKG_QUIET} -eq 1 ]] || printf '%s==>%s %s%s%s\n' "${C_BLU}" "${C_RST}" "${C_B}" "$*" "${C_RST}"; }
mpkg::step() { [[ ${MPKG_QUIET} -eq 1 ]] || printf '  %s->%s %s\n' "${C_DIM}" "${C_RST}" "$*"; }
mpkg::ok()   { [[ ${MPKG_QUIET} -eq 1 ]] || printf '  %s+%s %s\n' "${C_GRN}" "${C_RST}" "$*"; }
mpkg::warn() { printf '  %swarning:%s %s\n' "${C_YEL}" "${C_RST}" "$*" >&2; }
mpkg::err()  { printf '  %serror:%s %s\n'   "${C_RED}" "${C_RST}" "$*" >&2; }
mpkg::die()  { printf '%smpkg: %s%s\n' "${C_RED}" "$*" "${C_RST}" >&2; exit 1; }
mpkg::dbg()  { [[ ${MPKG_VERBOSE} -eq 1 ]] && printf '  %s%s%s\n' "${C_DIM}" "$*" "${C_RST}" >&2; return 0; }

# Run a command, quiet by default, everything captured in the package log.
# On failure the caller can show the tail with mpkg::log_tail.
mpkg::run() {
    mpkg::dbg "\$ $*"
    if [[ ${MPKG_VERBOSE} -eq 1 ]]; then
        if [[ -n "${MPKG_LOG}" ]]; then
            "$@" 2>&1 | tee -a "${MPKG_LOG}"
            return "${PIPESTATUS[0]}"
        fi
        "$@"
        return $?
    fi
    if [[ -n "${MPKG_LOG}" ]]; then
        "$@" >>"${MPKG_LOG}" 2>&1
    else
        "$@" >/dev/null 2>&1
    fi
}

mpkg::log_tail() {
    local n="${1:-25}"
    [[ -s "${MPKG_LOG}" ]] || return 0
    printf '  %s--- last %s lines of %s ---%s\n' "${C_DIM}" "${n}" "${MPKG_LOG}" "${C_RST}" >&2
    tail -n "${n}" "${MPKG_LOG}" | sed 's/^/  | /' >&2
}

# Report a failed stage with context, then return 1.
mpkg::stage_failed() {
    mpkg::err "$1"
    mpkg::log_tail 25
    return 1
}

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

# Prepend a path to a colon-separated variable, unless already present.
environment_prepend() {
    local var_name="$1" new_path="$2" current="${!1:-}"
    [[ -z "${new_path}" ]] && return 0
    [[ ":${current}:" == *":${new_path}:"* ]] && return 0
    if [[ -z "${current}" ]]; then export "${var_name}=${new_path}"
    else                          export "${var_name}=${new_path}:${current}"
    fi
}

# Locate a system CA bundle / directory. Everything mpkg builds links against
# the freshly built OpenSSL, whose own $PREFIX/ssl/certs is empty; without this
# every https:// download and every `git clone https://...` fails verification.
mpkg::detect_ca() {
    local f d
    MPKG_CA_BUNDLE="${SSL_CERT_FILE:-}"
    MPKG_CA_PATH="${SSL_CERT_DIR:-}"
    if [[ -z "${MPKG_CA_BUNDLE}" ]]; then
        for f in /etc/ssl/certs/ca-certificates.crt \
                 /etc/pki/tls/certs/ca-bundle.crt \
                 /etc/ssl/ca-bundle.pem \
                 /etc/ssl/cert.pem \
                 /usr/local/share/certs/ca-root-nss.crt \
                 /usr/share/ssl/certs/ca-bundle.crt; do
            [[ -r "$f" ]] && { MPKG_CA_BUNDLE="$f"; break; }
        done
    fi
    if [[ -z "${MPKG_CA_PATH}" ]]; then
        for d in /etc/ssl/certs /etc/pki/tls/certs; do
            [[ -d "$d" ]] && { MPKG_CA_PATH="$d"; break; }
        done
    fi
    export MPKG_CA_BUNDLE MPKG_CA_PATH
}

mpkg::core_init() {
    mpkg::colors

    # MPKG_OS / MPKG_ARCH override detection, e.g. to check which release
    # assets another platform would get: MPKG_OS=macos MPKG_ARCH=arm64.
    _OS="${MPKG_OS:-$(mpkg::detect_os)}"
    _ARCH="${MPKG_ARCH:-$(mpkg::detect_arch)}"
    _NPROCESSORS="${MPKG_JOBS:-$(mpkg::detect_jobs)}"
    # Other spellings release assets use: x86_64/aarch64, linux/darwin and the
    # Rust target triple (musl on Linux: static, so it runs on any distro).
    _UARCH="${_ARCH/amd64/x86_64}"; _UARCH="${_UARCH/arm64/aarch64}"
    _GOOS="${_OS/macos/darwin}"
    if [[ "${_OS}" == "macos" ]]; then _TRIPLE="${_UARCH}-apple-darwin"
    else                               _TRIPLE="${_UARCH}-unknown-linux-musl"
    fi
    export _OS _ARCH _NPROCESSORS _UARCH _GOOS _TRIPLE

    MPKG_PREFIX="${MPKG_PREFIX:-$HOME/.local}"
    MPKG_SOFT="${MPKG_PREFIX}/soft"
    MPKG_STATE="${MPKG_PREFIX}/var/mpkg"
    MPKG_DB="${MPKG_STATE}/db"
    MPKG_LOGDIR="${MPKG_STATE}/log"
    MPKG_WORK="${MPKG_WORK:-${MPKG_STATE}/work}"
    MPKG_ENVS="${MPKG_PREFIX}/envs"

    # Names the package scripts have always used.
    _PREFIX="${MPKG_PREFIX}"
    INSTALLATION_PATH="${MPKG_SOFT}"
    export MPKG_PREFIX MPKG_SOFT MPKG_STATE MPKG_DB MPKG_LOGDIR MPKG_WORK MPKG_ENVS
    export _PREFIX INSTALLATION_PATH

    mkdir -p "${MPKG_PREFIX}"/{bin,lib,lib64,include,share,soft,ssl} \
             "${MPKG_DB}" "${MPKG_LOGDIR}" "${MPKG_WORK}" 2>/dev/null

    environment_prepend "PATH"            "/usr/bin"
    environment_prepend "PATH"            "${HOME}/.cargo/bin"
    environment_prepend "PATH"            "${MPKG_PREFIX}/bin"
    environment_prepend "CPATH"           "${MPKG_PREFIX}/include"
    environment_prepend "CXXPATH"         "${MPKG_PREFIX}/include"
    environment_prepend "LIBRARY_PATH"    "/usr/lib"
    environment_prepend "LIBRARY_PATH"    "/usr/lib64"
    environment_prepend "LIBRARY_PATH"    "${MPKG_PREFIX}/lib64"
    environment_prepend "LIBRARY_PATH"    "${MPKG_PREFIX}/lib"
    environment_prepend "LD_LIBRARY_PATH" "/usr/lib"
    environment_prepend "LD_LIBRARY_PATH" "/usr/lib64"
    environment_prepend "LD_LIBRARY_PATH" "${MPKG_PREFIX}/lib64"
    environment_prepend "LD_LIBRARY_PATH" "${MPKG_PREFIX}/lib"
    environment_prepend "MANPATH"         "/usr/share/man"
    environment_prepend "MANPATH"         "${MPKG_PREFIX}/share/man"
    environment_prepend "PKG_CONFIG_PATH" "/usr/lib/pkgconfig"
    environment_prepend "PKG_CONFIG_PATH" "/usr/lib64/pkgconfig"
    environment_prepend "PKG_CONFIG_PATH" "${MPKG_PREFIX}/lib64/pkgconfig"
    environment_prepend "PKG_CONFIG_PATH" "${MPKG_PREFIX}/lib/pkgconfig"

    mpkg::detect_ca
    # Make the CA bundle authoritative for everything we spawn, including the
    # OpenSSL we just built and any curl linked against it.
    [[ -n "${MPKG_CA_BUNDLE}" ]] && export SSL_CERT_FILE="${MPKG_CA_BUNDLE}" \
                                           CURL_CA_BUNDLE="${MPKG_CA_BUNDLE}"
    [[ -n "${MPKG_CA_PATH}"   ]] && export SSL_CERT_DIR="${MPKG_CA_PATH}"
}

# Recomputed before every package: earlier installs extend CPATH / LIBRARY_PATH.
# -rpath is what lets a freshly built git find libcurl.so.4 without the caller
# having LD_LIBRARY_PATH set.
compute_build_flags() {
    _CFLAGS=$(  printf '%s' "${CPATH:-}"        | tr ':' '\n' | grep -v '^$' | sed 's/^/-I/' | tr '\n' ' ')
    _CXXFLAGS=$(printf '%s' "${CXXPATH:-}"      | tr ':' '\n' | grep -v '^$' | sed 's/^/-I/' | tr '\n' ' ')
    _LDFLAGS=$( printf '%s' "${LIBRARY_PATH:-}" | tr ':' '\n' | grep -v '^$' | sed 's/^/-L/' | tr '\n' ' ')
    _LDFLAGS="${_LDFLAGS}-Wl,-rpath,${MPKG_PREFIX}/lib -Wl,-rpath,${MPKG_PREFIX}/lib64"
    export _CFLAGS _CXXFLAGS _LDFLAGS
}
