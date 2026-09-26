#!/usr/bin/env bash
# Bootstrap entry point. Everything below is mpkg; this script only exists so
# that a fresh machine can run one command:
#
#   ./install.sh                 # install the whole workspace
#   ./install.sh mpkg            # just mpkg itself, into ~/.local/bin/mpkg
#   ./install.sh toolchain       # just openssl, curl, jq and git
#   ./install.sh doctor --fix    # any mpkg command still works
#   ./install.sh --help          # the full CLI
#
# Anything more specific is a job for ./mpkg/mpkg directly.

set -o pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
mpkg="${here}/mpkg/mpkg"

[[ -x "${mpkg}" ]] || { echo "install.sh: ${mpkg} is missing or not executable" >&2; exit 1; }

MPKG_COMMANDS="install remove rm uninstall upgrade up list ls available search avail
info show deps tree order resolve link unlink relink prune adopt clean log env doctor
check help version i"

# Find the first non-option word; if it is not a command, the caller named a
# package and means 'install'.
first=""
for word in "$@"; do
    case "${word}" in
        -*) continue ;;
        *)  first="${word}"; break ;;
    esac
done

if [[ -z "${first}" ]]; then
    set -- "$@" install workspace
elif ! printf '%s\n' ${MPKG_COMMANDS} | grep -qx -- "${first}"; then
    set -- install "$@"
fi

exec "${mpkg}" "$@"
