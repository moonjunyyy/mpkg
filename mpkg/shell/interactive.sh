# mpkg setup for interactive bash and zsh, after env.sh. Like env.sh it knows
# no package: prompts, plugins and shell functions come from the fragments
# installed packages declare, in $MPKG_PREFIX/var/mpkg/shell/rc.d/, loaded in
# the order of their names (NN-<package>.sh).

: "${MPKG_PREFIX:=${HOME}/.local}"

# mpkg environments:  mpkg_activate <name>  /  mpkg_deactivate
mpkg_activate() {
    if [ -f "${MPKG_PREFIX}/envs/$1/activate" ]; then . "${MPKG_PREFIX}/envs/$1/activate"
    else echo "mpkg_activate: no environment '$1'" >&2; return 1
    fi
}

_mpkg_d="${MPKG_PREFIX}/var/mpkg/shell/rc.d"
for _mpkg_f in $(ls "${_mpkg_d}" 2>/dev/null); do
    case "${_mpkg_f}" in *.sh) . "${_mpkg_d}/${_mpkg_f}" ;; esac
done
unset _mpkg_d _mpkg_f

# Upgrade notice. No network here: this reads what the last `mpkg update`
# found, and when that check is older than MPKG_UPDATE_INTERVAL minutes
# (default a day) starts a new one in the background for the next shell.
# MPKG_NO_UPDATE_CHECK=1 turns both off.
_mpkg_update_notice() {
    [ -z "${MPKG_NO_UPDATE_CHECK:-}" ] || return 0
    command -v mpkg >/dev/null 2>&1 || return 0
    _mpkg_st="${MPKG_PREFIX}/var/mpkg"
    if [ ! -f "${_mpkg_st}/updates.checked" ] \
       || [ -n "$(find "${_mpkg_st}/updates.checked" -mmin +"${MPKG_UPDATE_INTERVAL:-1440}" 2>/dev/null)" ]; then
        (nohup mpkg update --auto </dev/null >/dev/null 2>&1 &)
    fi
    [ -s "${_mpkg_st}/updates" ] || return 0
    # A line counts while the package is still at the version it was checked at.
    _mpkg_up=""
    _mpkg_n=0
    while read -r _mpkg_p _mpkg_have _mpkg_new; do
        [ -n "${_mpkg_new}" ] || continue
        [ "$(sed -n 's/^version=//p' "${_mpkg_st}/db/${_mpkg_p}" 2>/dev/null)" = "${_mpkg_have}" ] || continue
        _mpkg_up="${_mpkg_up} ${_mpkg_p}"
        _mpkg_n=$((_mpkg_n + 1))
    done < "${_mpkg_st}/updates"
    [ "${_mpkg_n}" -gt 0 ] \
        && printf 'mpkg: %s upgrade(s) available:%s  (mpkg upgrade)\n' "${_mpkg_n}" "${_mpkg_up}"
    return 0
}
_mpkg_update_notice
unset -f _mpkg_update_notice
unset _mpkg_st _mpkg_up _mpkg_n _mpkg_p _mpkg_have _mpkg_new
