# mpkg itself, installed into the prefix like any other executable:
#
#   soft/mpkg-<version>/libexec/mpkg/mpkg/{mpkg,lib/,packages/}
#   soft/mpkg-<version>/libexec/mpkg/nvim/      configuration packages install
#   soft/mpkg-<version>/bin/mpkg                wrapper, linked to $PREFIX/bin
#
# The version is mpkg's own plus a hash of everything copied, so installing
# again after the checkout changed builds a new tree and drops the old one.
# The installed copy remembers the checkout it came from: `mpkg upgrade`
# (after a `git pull` there) reinstalls from it.

mpkg_inherit pkgcommon

MPKG_TITLE="mpkg"
MPKG_DESC="This package manager, installed into the prefix it manages"
MPKG_HOMEPAGE="https://github.com/moonjunyyy/m00nny_workspace_init"
MPKG_KIND="binary"
MPKG_PROBE_CMD="mpkg"
MPKG_DESTDIR='mpkg-${version}'

# What is copied, relative to the source root.
MPKG_SELF_FILES=(mpkg/mpkg mpkg/README.md mpkg/lib mpkg/packages nvim)

mpkg_run() {
    mpkg_discover || return 1
    mpkg::report_versions
    if mpkg::is_current; then
        MPKG_STATUS="current"
        mpkg_cleanup
        return 0
    fi
    mpkg_install || return 1
    mpkg_link    || return 1
    mpkg::self_drop_old_tree
    mpkg_cleanup
    MPKG_STATUS="installed"
}

# The checkout to install from: this one, unless this is an installed copy
# whose checkout is still around.
mpkg::self_source() {
    local src="${MPKG_ROOT}" origin
    if [[ -r "${MPKG_ROOT}/.source" ]]; then
        origin="$(cat "${MPKG_ROOT}/.source")"
        [[ -x "${origin}/mpkg/mpkg" ]] && src="${origin}"
    fi
    printf '%s\n' "${src}"
}

mpkg_discover() {
    MPKG_SELF_SRC="$(mpkg::self_source)"
    local f stage="${MPKG_WORK}/mpkg-self-digest"
    MPKG_TMPFILES+=(mpkg-self-digest)
    rm -rf "${stage}" && mkdir -p "${stage}/mpkg" || return 1
    for f in "${MPKG_SELF_FILES[@]}"; do
        [[ -e "${MPKG_SELF_SRC}/${f}" ]] || { mpkg::err "missing ${MPKG_SELF_SRC}/${f}"; return 1; }
        mpkg::copy_clean "${MPKG_SELF_SRC}/${f}" "${stage}/${f}" || return 1
    done
    local ver
    ver="$(sed -n 's/^MPKG_VERSION_STR="\(.*\)"$/\1/p' "${MPKG_SELF_SRC}/mpkg/mpkg")"
    MPKG_VERSION="${ver:-0}+$(mpkg::tree_digest "${stage}")"
    MPKG_TAG="${MPKG_VERSION}"
    MPKG_DEST_NAME="$(mpkg::render "${MPKG_DESTDIR}")"
    mpkg::step "source: ${MPKG_SELF_SRC}"
}

mpkg_install() {
    local tree="${MPKG_SOFT}/${MPKG_DEST_NAME}"
    local payload="${tree}/libexec/mpkg"

    # Reinstalling the very tree this process runs from (--force from the
    # installed copy): the files are already right, only the links are redone.
    if [[ "${MPKG_ROOT}" == "${payload}" ]]; then
        mpkg::step "running from ${tree}; relinking only"
        return 0
    fi

    rm -rf "${tree:?}" && mkdir -p "${payload}" "${tree}/bin" || return 1
    cp -R "${MPKG_WORK}/mpkg-self-digest/." "${payload}/" || return 1
    printf '%s\n' "${MPKG_SELF_SRC}" > "${payload}/.source"

    # A wrapper rather than a symlink: $PREFIX/bin/mpkg is itself a link into
    # this tree, and the script finds lib/ and packages/ next to its real path.
    cat > "${tree}/bin/mpkg" <<WRAPPER
#!/usr/bin/env bash
exec "${payload}/mpkg/mpkg" "\$@"
WRAPPER
    chmod +x "${tree}/bin/mpkg" "${payload}/mpkg/mpkg" || return 1
    mpkg::step "installed ${tree}"
}

# Like drop_old_tree, except that the tree this process is running from stays:
# the rest of this run still sources packages from it. 'mpkg gc' collects it.
mpkg::self_drop_old_tree() {
    local old; old="$(mpkg::db_dest "${MPKG_NAME}" 2>/dev/null)"
    if [[ -n "${old}" && "${MPKG_ROOT}" == "${MPKG_SOFT}/${old}/"* ]]; then
        mpkg::step "kept ${old} while it is running; 'mpkg gc' removes it later"
        return 0
    fi
    mpkg::drop_old_tree
}

mpkg_post_install() {
    case ":${PATH}:" in
        *":${MPKG_PREFIX}/bin:"*) ;;
        *) mpkg::warn "${MPKG_PREFIX}/bin is not on PATH; add it (shell-config does)" ;;
    esac
}
