# Installs the editor configuration that ships with this repository (nvim/) into
# ~/.config/nvim. It is a package like any other so the solver pulls in the
# runtimes the plugins need (git for lazy.nvim, the tree-sitter CLI and a C
# compiler for nvim-treesitter's parsers, a Python for pynvim, a Ruby for the
# neovim gem, a JDK for the Java tooling).
#
# The version is a hash of nvim/, so re-running the install after the
# configuration changed in the repository replaces the installed copy. A copy
# that was edited in place, or a configuration mpkg did not write (such as the
# old init.vim), is moved aside to ~/.config/nvim.mpkg-backup.<time> first.

mpkg_inherit pkgcommon

MPKG_TITLE="Neovim configuration"
MPKG_DESC="init.lua and lua/ (lazy.nvim, LSP, tree-sitter), plugins, parsers and providers"
MPKG_KIND="config"
MPKG_UNVERSIONED=1
MPKG_PROBE_CMD=""
MPKG_DEPENDS=(neovim git uv ruby tree-sitter jdk)

MPKG_NVIM_SRC="${MPKG_ROOT}/nvim"
MPKG_NVIM_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/nvim"
MPKG_NVIM_STAMP=".mpkg-stamp"
# What the stamp does not cover: itself, and the lockfile, which lazy.nvim
# rewrites on every plugin update -- that is not an edit.
MPKG_NVIM_SKIP="${MPKG_NVIM_STAMP} lazy-lock.json"

mpkg_run() {
    [[ -r "${MPKG_NVIM_SRC}/init.lua" ]] || { mpkg::err "missing ${MPKG_NVIM_SRC}/init.lua"; return 1; }
    command -v nvim >/dev/null 2>&1 || { mpkg::err "nvim is not on PATH"; return 1; }

    MPKG_VERSION="$(mpkg::tree_digest "${MPKG_NVIM_SRC}")"
    mpkg::report_versions
    if [[ ${MPKG_FORCE:-0} -eq 0 && "${MPKG_VERSION}" == "${MPKG_INSTALLED_VERSION}" ]] \
       && mpkg::nvim_is_ours; then
        MPKG_STATUS="current"
        return 0
    fi

    mpkg::nvim_write_config || return 1
    mpkg::nvim_vimrc
    mpkg::nvim_providers
    mpkg::nvim_plugins

    MPKG_DEST_NAME=""
    MPKG_STATUS="installed"
}

# The installed directory is exactly what mpkg wrote there last time.
mpkg::nvim_is_ours() {
    local stamp="${MPKG_NVIM_DIR}/${MPKG_NVIM_STAMP}"
    [[ -f "${stamp}" ]] || return 1
    [[ "$(MPKG_DIGEST_SKIP="${MPKG_NVIM_SKIP}" mpkg::tree_digest "${MPKG_NVIM_DIR}")" \
       == "$(cat "${stamp}")" ]]
}

mpkg::nvim_write_config() {
    local backup
    if [[ -e "${MPKG_NVIM_DIR}" || -L "${MPKG_NVIM_DIR}" ]]; then
        if mpkg::nvim_is_ours; then
            rm -rf "${MPKG_NVIM_DIR:?}"
        else
            backup="${MPKG_NVIM_DIR}.mpkg-backup.$(date +%Y%m%d-%H%M%S)"
            mv "${MPKG_NVIM_DIR}" "${backup}" || return 1
            mpkg::warn "moved the existing configuration to ${backup}"
        fi
    fi

    mpkg::step "installing ${MPKG_NVIM_DIR} from the repository"
    mkdir -p "$(dirname "${MPKG_NVIM_DIR}")" || return 1
    cp -R "${MPKG_NVIM_SRC}" "${MPKG_NVIM_DIR}" || return 1
    MPKG_DIGEST_SKIP="${MPKG_NVIM_SKIP}" mpkg::tree_digest "${MPKG_NVIM_DIR}" \
        > "${MPKG_NVIM_DIR}/${MPKG_NVIM_STAMP}"

    local plugged="${XDG_DATA_HOME:-${HOME}/.local/share}/nvim/plugged"
    [[ -d "${plugged}" ]] && mpkg::step "the old vim-plug plugins in ${plugged} are unused now and can be deleted"
    return 0
}

# ~/.vimrc is for plain vim; the Neovim configuration no longer reads it.
mpkg::nvim_vimrc() {
    if [[ -f "${HOME}/.vimrc" && ${MPKG_FORCE:-0} -eq 0 ]]; then
        return 0
    fi
    mpkg::step "writing ~/.vimrc"
    cat > "${HOME}/.vimrc" <<'VIMRC'
set nocompatible
set hlsearch
set encoding=utf8
set fileencodings=utf-8,euc-kr,cp949
set bs=indent,eol,start
set history=1000
set ruler
set nobackup
set title
set showmatch
set nowrap
set wildmenu
set wildmode=longest:full,full
set cursorline
set tabstop=4
set shiftwidth=4
set softtabstop=4
set expandtab
set clipboard+=unnamedplus
set number
syntax on
filetype plugin indent on
VIMRC
}

# Language providers. None of them is fatal. The Python venv lives in nvim's
# data directory, where options.lua looks for it, so replacing the
# configuration directory does not throw it away.
mpkg::nvim_providers() {
    local venv="${XDG_DATA_HOME:-${HOME}/.local/share}/nvim/venv"
    if command -v uv >/dev/null 2>&1; then
        mpkg::step "setting up the Python provider in ${venv}"
        { [[ -x "${venv}/bin/python" ]] || mpkg::run uv venv "${venv}"; } \
            && mpkg::run uv pip install --python "${venv}/bin/python" --upgrade pynvim \
            || mpkg::warn "could not set up the Python provider"
    fi
    if command -v gem >/dev/null 2>&1; then
        mpkg::step "installing the Ruby provider"
        mpkg::run gem install --no-document neovim || mpkg::warn "could not install the neovim gem"
    fi
}

# Plugins at the commits in lazy-lock.json, then the tree-sitter parsers, so
# the first interactive start has nothing left to download. Failures are
# warnings: nvim installs whatever is missing on its next start anyway.
mpkg::nvim_plugins() {
    mpkg::step "installing plugins (lazy.nvim, pinned by lazy-lock.json)"
    mpkg::run nvim --headless '+Lazy! restore' +qa || mpkg::warn "lazy.nvim reported errors"

    mpkg::step "installing tree-sitter parsers"
    local script="${MPKG_WORK}/nvim-parsers.lua"
    MPKG_TMPFILES+=(nvim-parsers.lua)
    cat > "${script}" <<'LUA'
local ts = require('nvim-treesitter')
local wanted = require('config.languages').parsers
pcall(function() ts.install(wanted):wait(900000) end)
local have = ts.get_installed('parsers')
local missing = vim.tbl_filter(function(p) return not vim.list_contains(have, p) end, wanted)
if #missing > 0 then
    io.stdout:write('mpkg-parsers-missing ' .. table.concat(missing, ' ') .. '\n')
end
LUA
    mpkg::run nvim --headless +"luafile ${script}" +qa
    local missing; missing="$(sed -n 's/.*mpkg-parsers-missing //p' "${MPKG_LOG}")"
    [[ -n "${missing}" ]] && mpkg::warn "parsers not installed: ${missing}"
    return 0
}

mpkg_link() { return 0; }

mpkg_remove() {
    mpkg::warn "leaving ${MPKG_NVIM_DIR} in place; delete it by hand if it should go"
}
