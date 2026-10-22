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

# Keep in step with the dispatch table at the bottom of mpkg/mpkg.
MPKG_COMMANDS="install i remove rm uninstall upgrade up update outdated list ls available search avail
info show deps tree order resolve link unlink relink prune adopt clean gc venv envs
log env doctor check help version"

# Find the first non-option word; if it is not a command, the caller named a
# package and means 'install'. The values of --prefix and -j are not words.
first=""
skip=0
for word in "$@"; do
    (( skip )) && { skip=0; continue; }
    case "${word}" in
        --prefix|-j|--jobs) skip=1 ;;
        -*) ;;
        *)  first="${word}"; break ;;
    esac
done

if [[ -z "${first}" ]]; then
    set -- "$@" install workspace
elif ! printf '%s\n' ${MPKG_COMMANDS} | grep -qx -- "${first}"; then
    set -- install "$@"
fi

exec "${mpkg}" "$@"
