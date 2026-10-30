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

# nproc is GNU; getconf covers Linux, macOS and the BSDs; sysctl is the last
# resort on BSDs whose getconf lacks the variable.
mpkg::detect_jobs() {
    local n
    n="$(nproc 2>/dev/null)" \
        || n="$(getconf _NPROCESSORS_ONLN 2>/dev/null)" \
        || n="$(sysctl -n hw.ncpu 2>/dev/null)"
    [[ "${n}" =~ ^[0-9]+$ && "${n}" -gt 0 ]] && echo "${n}" || echo 1
}

# Most source trees assume GNU make. On the BSDs `make` is bmake and GNU make
# is `gmake`; use the GNU one wherever it is.
mpkg::detect_make() {
    if make --version 2>/dev/null | grep -q 'GNU Make'; then echo make
    elif command -v gmake >/dev/null 2>&1;             then echo gmake
    else echo make
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
    # Exported as MAKE too, which autoconf-generated configure scripts honour.
    MPKG_MAKE="${MPKG_MAKE:-$(mpkg::detect_make)}"
    MAKE="${MPKG_MAKE}"
    export MPKG_MAKE MAKE
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

    # Library directories. lib64 is the Linux multilib convention; Apple's
    # toolchain has only lib, and an empty lib64 there is one more search path
    # for ld to look at on every link.
    case "${_OS}" in
        macos) MPKG_LIBDIRS="lib" ;;
        *)     MPKG_LIBDIRS="lib lib64" ;;
    esac
    export MPKG_LIBDIRS

    # Where the system's own headers are: the SDK on macOS (it has no
    # /usr/include), the usual directories elsewhere. mpkg::have_header looks
    # here to decide whether a library has to be built (zlib, libyaml). Set
    # in the environment, it is taken as is (MPKG_SYSINC=/none: build them all).
    if [[ -z "${MPKG_SYSINC:-}" ]]; then
        MPKG_SYSINC="/usr/local/include:/usr/include"
        if [[ "${_OS}" == macos ]]; then
            local sdk
            sdk="$(xcrun --show-sdk-path 2>/dev/null)"
            [[ -n "${sdk}" ]] && MPKG_SYSINC="${sdk}/usr/include:${MPKG_SYSINC}"
        fi
    fi
    export MPKG_SYSINC

    local sub
    for sub in bin ${MPKG_LIBDIRS} include share soft ssl; do
        mkdir -p "${MPKG_PREFIX}/${sub}" 2>/dev/null
    done
    mkdir -p "${MPKG_DB}" "${MPKG_LOGDIR}" "${MPKG_WORK}" 2>/dev/null

    # What only a build needs. The system library directories are the
    # toolchain's defaults and are left off: on macOS /usr/lib64 does not exist
    # and /usr/lib holds no linkable libraries (they live in the SDK), and
    # Apple's ld warns about both.
    environment_prepend "PATH"            "/usr/bin"
    local d
    for d in /usr/lib/pkgconfig /usr/lib64/pkgconfig /usr/libdata/pkgconfig; do
        [[ -d "${d}" ]] && environment_prepend "PKG_CONFIG_PATH" "${d}"
    done
    # Then the environment every shell gets: the prefix and whatever the
    # installed packages declare (lib/shell.sh) -- ~/.cargo/bin, JAVA_HOME, ...
    mpkg::env_load
    environment_prepend "CXXPATH"         "${MPKG_PREFIX}/include"

    mpkg::detect_ca
    # Make the CA bundle authoritative for everything we spawn, including the
    # OpenSSL we just built and any curl linked against it.
    [[ -n "${MPKG_CA_BUNDLE}" ]] && export SSL_CERT_FILE="${MPKG_CA_BUNDLE}" \
                                           CURL_CA_BUNDLE="${MPKG_CA_BUNDLE}"
    [[ -n "${MPKG_CA_PATH}"   ]] && export SSL_CERT_DIR="${MPKG_CA_PATH}"
}

# ---------------------------------------------------------------------------
# Locking
# ---------------------------------------------------------------------------

# One mutating mpkg per prefix at a time: two concurrent runs share the work
# directory and race on the database and the symlink farm. mkdir is atomic,
# including on NFS, which flock is not. The lock records host and pid, so a
# lock left by a crashed run on this host is taken over; one held from another
# host is never guessed at.
mpkg::lock() {
    [[ -n "${_MPKG_LOCKED:-}" ]] && return 0   # held by us or by our parent mpkg
    local lock="${MPKG_STATE}/lock" host pid me
    me="$(hostname 2>/dev/null || uname -n)"
    mkdir -p "${MPKG_STATE}" 2>/dev/null
    if ! mkdir "${lock}" 2>/dev/null; then
        # No owner yet: the other run may be between its mkdir and the write.
        [[ -f "${lock}/owner" ]] || sleep 1
        host="$(sed -n 's/^host=//p' "${lock}/owner" 2>/dev/null)"
        pid="$( sed -n 's/^pid=//p'  "${lock}/owner" 2>/dev/null)"
        if [[ -n "${host}" && "${host}" != "${me}" ]]; then
            mpkg::die "${MPKG_PREFIX} is locked by mpkg on ${host} (pid ${pid:-?}); if that run is gone: rm -rf ${lock}"
        fi
        if [[ -n "${pid}" ]] && mpkg::pid_alive "${pid}"; then
            mpkg::die "another mpkg (pid ${pid}) is working on ${MPKG_PREFIX}"
        fi
        mpkg::warn "taking over the stale lock of pid ${pid:-?}"
        rm -rf "${lock}"
        mkdir "${lock}" 2>/dev/null || mpkg::die "cannot lock ${MPKG_PREFIX} (${lock})"
    fi
    printf 'host=%s\npid=%s\n' "${me}" "$$" > "${lock}/owner"
    _MPKG_LOCKED="${lock}"
    export _MPKG_LOCKED
    _MPKG_LOCK_OWNER=$$
    trap 'mpkg::unlock' EXIT
    trap 'mpkg::err "interrupted"; exit 130' INT TERM HUP
}

# kill -0 fails for a live process of another user too; EPERM still means alive.
mpkg::pid_alive() {
    local out
    out="$(kill -0 "$1" 2>&1)" && return 0
    [[ "${out}" == *[Pp]ermitted* || "${out}" == *EPERM* ]]
}

mpkg::unlock() {
    [[ -n "${_MPKG_LOCKED:-}" && "${_MPKG_LOCK_OWNER:-}" == "$$" ]] || return 0
    rm -rf "${_MPKG_LOCKED}"
    _MPKG_LOCKED=""
}

# Is <dir> one the compiler and linker search anyway? Passing those again is
# at best noise; -I/usr/include breaks libstdc++'s #include_next, and on macOS
# -L/usr/lib64 draws a "directory not found" warning from ld.
mpkg::is_system_dir() {
    case "${1%/}" in
        /lib|/lib64|/usr/lib|/usr/lib64|/usr/include) return 0 ;;
    esac
    # Apple's ld and clang search /usr/local/lib and /usr/local/include by
    # default as well; naming them again only repeats the default.
    if [[ "${_OS:-}" == macos ]]; then
        case "${1%/}" in /usr/local/lib|/usr/local/include) return 0 ;; esac
    fi
    return 1
}

# path_flags <flag> <colon-list> — one <flag><dir> per directory that exists
# and is not a system default, each directory once, in list order.
mpkg::path_flags() {
    local flag="$1" d seen=":" out=""
    local -a dirs
    IFS=':' read -r -a dirs <<< "$2"
    for d in "${dirs[@]}"; do
        [[ -n "${d}" && -d "${d}" ]] || continue
        mpkg::is_system_dir "${d}" && continue
        [[ "${seen}" == *":${d}:"* ]] && continue
        seen="${seen}${d}:"
        out="${out}${flag}${d} "
    done
    printf '%s' "${out}"
}

# path_clean <VAR> [all] — rewrite the colon list <VAR> in place: each
# directory once, only those that exist, and, unless "all", none of the
# toolchain's own defaults (mpkg::is_system_dir). Empty afterwards: unset.
mpkg::path_clean() {
    local var="$1" all="${2:-}" d seen=":" out=""
    local -a dirs
    IFS=':' read -r -a dirs <<< "${!var:-}"
    for d in "${dirs[@]}"; do
        [[ "${d}" == / ]] || d="${d%/}"
        [[ -n "${d}" && -d "${d}" ]] || continue
        [[ -z "${all}" ]] && mpkg::is_system_dir "${d}" && continue
        [[ "${seen}" == *":${d}:"* ]] && continue
        seen="${seen}${d}:"
        out="${out:+${out}:}${d}"
    done
    if [[ -n "${out}" ]]; then export "${var}=${out}"; else unset "${var}"; fi
}

# Recomputed before every package: earlier installs extend CPATH / LIBRARY_PATH.
# -rpath is what lets a freshly built git find libcurl.so.4 without the caller
# having LD_LIBRARY_PATH set.
#
# Every flag must be clean on every linker: Ruby's configure, among others,
# treats any linker warning as an invalid LDFLAGS, and Apple's ld warns about
# missing -L directories and repeated -rpath entries.
#
# The search-path variables reach the toolchain directly as well, not only
# through these flags: gcc and Apple's clang hand every LIBRARY_PATH entry to
# ld as a -L. A directory that does not exist there (/usr/lib64 on a Mac, left
# by a shell profile) makes ld warn on every link -- and Ruby's configure then
# rejects an LDFLAGS that never contained it. So the variables are cleaned
# first, not just the flags.
compute_build_flags() {
    mpkg::path_clean LIBRARY_PATH
    mpkg::path_clean CPATH
    mpkg::path_clean CXXPATH
    mpkg::path_clean PKG_CONFIG_PATH all
    mpkg::path_clean LD_LIBRARY_PATH all

    local rpath="" sub
    for sub in ${MPKG_LIBDIRS:-lib lib64}; do
        rpath="${rpath:+${rpath}:}${MPKG_PREFIX}/${sub}"
    done
    _CFLAGS="$(  mpkg::path_flags -I "${CPATH:-}")"
    _CXXFLAGS="$(mpkg::path_flags -I "${CXXPATH:-}")"
    _LDFLAGS="$( mpkg::path_flags -L "${LIBRARY_PATH:-}")"
    _LDFLAGS="${_LDFLAGS}$(mpkg::path_flags -Wl,-rpath, "${rpath}")"
    _CFLAGS="${_CFLAGS% }"; _CXXFLAGS="${_CXXFLAGS% }"; _LDFLAGS="${_LDFLAGS% }"
    export _CFLAGS _CXXFLAGS _LDFLAGS
}
