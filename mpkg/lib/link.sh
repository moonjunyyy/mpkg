# mpkg / lib/link.sh — stow-style linking of a package tree into the prefix.
#
# Every package installs into $MPKG_SOFT/<dest> and is then symlinked into
# $MPKG_PREFIX. The original implementation walked the tree with `find -type f`,
# which silently dropped the *symlinks* a package ships. That is not cosmetic:
# a shared library installs as
#
#     lib/libcurl.so     -> libcurl.so.4.8.0   (symlink)
#     lib/libcurl.so.4   -> libcurl.so.4.8.0   (symlink)
#     lib/libcurl.so.4.8.0                     (regular file)
#
# and only the last one was linked. With no $PREFIX/lib/libcurl.so, `-lcurl`
# resolves to the static libcurl.a, whose link fails on the undefined zlib/zstd
# symbols -- so git's configure concludes curl is unusable, sets NO_CURL, and
# builds a git with no git-remote-http/git-remote-https. That is exactly why
# `git clone https://...` failed with "unable to find remote helper for https".
#
# The walk below takes regular files *and* symlinks.

# Emit every linkable path inside a package tree, relative to the tree root.
mpkg::link_entries() {
    local root="$1"
    [[ -d "${root}" ]] || return 1
    find "${root}" -mindepth 1 \( -type f -o -type l \) -printf '%P\0' 2>/dev/null \
        || find "${root}" -mindepth 1 \( -type f -o -type l \) -print0 \
           | while IFS= read -r -d '' p; do printf '%s\0' "${p#"${root}"/}"; done
}

# link_tree <tree> <target-prefix> <manifest>
# Symlink every entry of <tree> into <target-prefix>, recording what was linked
# in <manifest>. Shared by the base prefix and by environments (lib/venv.sh).
mpkg::link_tree() {
    local root="$1" into="$2" manifest="$3"
    local rel target n=0 clashes=0

    [[ -d "${root}" ]] || { mpkg::err "nothing to link: ${root} is missing"; return 1; }

    : > "${manifest}"
    while IFS= read -r -d '' rel; do
        target="${into}/${rel}"
        mkdir -p "$(dirname "${target}")"
        if [[ -L "${target}" ]]; then
            rm -f "${target}"
        elif [[ -e "${target}" ]]; then
            if [[ ${MPKG_FORCE:-0} -eq 1 ]]; then
                mv -f "${target}" "${target}.mpkg-orig"
                mpkg::warn "kept existing file as ${target}.mpkg-orig"
            else
                mpkg::err "collision: ${target} exists and is not an mpkg link"
                clashes=$(( clashes + 1 ))
                continue
            fi
        fi
        ln -s "${root}/${rel}" "${target}" || { mpkg::err "cannot link ${target}"; return 1; }
        printf '%s\n' "${rel}" >> "${manifest}"
        n=$(( n + 1 ))
    done < <(mpkg::link_entries "${root}" | sort -z)

    if (( clashes > 0 )); then
        mpkg::err "${clashes} collision(s); re-run with --force to displace them"
        return 1
    fi
    mpkg::step "linked ${n} entries into ${into}"
}

# unlink_manifest <target-prefix> <manifest> — drop the links a manifest lists.
mpkg::unlink_manifest() {
    local into="$1" manifest="$2" rel target n=0
    [[ -f "${manifest}" ]] || return 0
    while IFS= read -r rel; do
        target="${into}/${rel}"
        [[ -L "${target}" ]] && { rm -f "${target}"; n=$(( n + 1 )); }
    done < "${manifest}"
    mpkg::step "removed ${n} links"
    rm -f "${manifest}"
}

# link <name> <dest-dir-name> — into the base prefix.
mpkg::link() {
    mpkg::link_tree "${MPKG_SOFT}/$2" "${MPKG_PREFIX}" "$(mpkg::db_files "$1")"
}

# unlink <name> — drop only the links this package owns in the base prefix.
mpkg::unlink() {
    local name="$1"
    local manifest; manifest="$(mpkg::db_files "${name}")"
    local dest rel target n=0

    if [[ ! -f "${manifest}" ]]; then
        dest="$(mpkg::db_dest "${name}")"
        [[ -n "${dest}" && -d "${MPKG_SOFT}/${dest}" ]] || return 0
        while IFS= read -r -d '' rel; do
            target="${MPKG_PREFIX}/${rel}"
            [[ -L "${target}" ]] && { rm -f "${target}"; n=$(( n + 1 )); }
        done < <(mpkg::link_entries "${MPKG_SOFT}/${dest}")
        mpkg::step "removed ${n} links"
        return 0
    fi
    mpkg::unlink_manifest "${MPKG_PREFIX}" "${manifest}"
}

# Backwards-compatible names used by package scripts.
link_package()   { mpkg::link "${MPKG_NAME}" "$1"; }
unlink_package() { mpkg::unlink "${MPKG_NAME}"; }

# Drop links that point at a package tree that no longer exists.
mpkg::prune_links() {
    local d n=0 t
    for d in bin lib lib64 include share libexec; do
        [[ -d "${MPKG_PREFIX}/${d}" ]] || continue
        while IFS= read -r -d '' t; do
            if [[ "$(readlink "${t}")" == "${MPKG_SOFT}/"* ]] && [[ ! -e "${t}" ]]; then
                rm -f "${t}"; n=$(( n + 1 ))
            fi
        done < <(find "${MPKG_PREFIX}/${d}" -type l -print0 2>/dev/null)
    done
    mpkg::say "pruned ${n} dangling link(s)"
}
