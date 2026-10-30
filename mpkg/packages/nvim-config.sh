# The Neovim configuration in config/nvim/ (lazy.nvim, the built-in LSP
# client, nvim-treesitter), installed as ~/.config/nvim by configcommon. After
# installing it, the plugins are installed at the commits in lazy-lock.json
# and the tree-sitter parsers built, so the first start downloads nothing;
# the dependencies are what that needs (git for lazy.nvim, the tree-sitter CLI
# and a C compiler for the parsers, uv for the Python provider, ruby for the
# neovim gem, a JDK for the Java tooling).

mpkg_inherit configcommon

MPKG_TITLE="Neovim configuration"
MPKG_DESC="init.lua and lua/ (lazy.nvim, LSP, tree-sitter), plugins, parsers and providers"
MPKG_DEPENDS=(neovim git uv ruby tree-sitter jdk)
# lazy.nvim rewrites its lockfile on every plugin update; that is not an edit.
MPKG_CONFIG_KEEP=(lazy-lock.json)

mpkg_post_install() {
    command -v nvim >/dev/null 2>&1 || { mpkg::warn "nvim is not on PATH; plugins not installed"; return 0; }
    mpkg::nvim_providers
    mpkg::nvim_plugins
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
