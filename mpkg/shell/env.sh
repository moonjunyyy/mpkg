# mpkg environment, POSIX sh. Sourced by every shell's startup files (through
# the block shell-config adds) and by mpkg itself before it builds anything,
# so a shell and a build see the same environment. Safe to source any number
# of times.
#
# Nothing in here knows about a particular package. Each installed package
# that needs something (JAVA_HOME, ~/go/bin on PATH, ...) declares it, and
# mpkg writes that out as a fragment in $MPKG_PREFIX/var/mpkg/shell/env.d/,
# which is loaded below. Installing or removing a package changes the next
# shell; this file never needs regenerating.

: "${MPKG_PREFIX:=${HOME}/.local}"
export MPKG_PREFIX

# mpkg_path <VAR> <dir> — move (or add) <dir> to the front of the colon list
# <VAR>, when <dir> exists. Moving, not just adding, matters on macOS, where
# /etc/zprofile's path_helper puts the system directories back in front.
mpkg_path() {
    [ -d "$2" ] || return 0
    eval "_mpkg_cur=\":\${$1:-}:\""
    while :; do
        case "${_mpkg_cur}" in
            *":$2:"*) _mpkg_cur="${_mpkg_cur%%:"$2":*}:${_mpkg_cur#*:"$2":}" ;;
            *) break ;;
        esac
    done
    _mpkg_cur="${_mpkg_cur#:}"; _mpkg_cur="${_mpkg_cur%:}"
    if [ -n "${_mpkg_cur}" ]; then eval "export $1=\"\$2:\${_mpkg_cur}\""
    else                           eval "export $1=\"\$2\""
    fi
    unset _mpkg_cur
}

# Package fragments first, so that the prefix's own directories, added after
# them, end up in front of whatever a package puts on PATH. (ls, not a glob:
# zsh aborts on a glob that matches nothing.)
_mpkg_d="${MPKG_PREFIX}/var/mpkg/shell/env.d"
for _mpkg_f in $(ls "${_mpkg_d}" 2>/dev/null); do
    case "${_mpkg_f}" in *.sh) . "${_mpkg_d}/${_mpkg_f}" ;; esac
done

# The prefix itself. An empty MANPATH element keeps man's built-in search path.
if [ -d "${MPKG_PREFIX}/share/man" ]; then
    [ -n "${MANPATH:-}" ] || export MANPATH=":"
    mpkg_path MANPATH     "${MPKG_PREFIX}/share/man"
fi
mpkg_path PKG_CONFIG_PATH "${MPKG_PREFIX}/lib64/pkgconfig"
mpkg_path PKG_CONFIG_PATH "${MPKG_PREFIX}/lib/pkgconfig"
mpkg_path LIBRARY_PATH    "${MPKG_PREFIX}/lib64"
mpkg_path LIBRARY_PATH    "${MPKG_PREFIX}/lib"
mpkg_path CPATH           "${MPKG_PREFIX}/include"
# dyld ignores LD_LIBRARY_PATH; macOS binaries find the prefix by rpath.
case "${OSTYPE:-}" in
    darwin*) ;;
    *) mpkg_path LD_LIBRARY_PATH "${MPKG_PREFIX}/lib64"
       mpkg_path LD_LIBRARY_PATH "${MPKG_PREFIX}/lib" ;;
esac
mpkg_path PATH            "${MPKG_PREFIX}/bin"

unset _mpkg_d _mpkg_f
