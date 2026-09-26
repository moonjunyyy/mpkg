# Installs the language servers the Neovim configuration asks mason-lspconfig
# for, up front and synchronously, instead of in the background on the first
# start of nvim. The list is the `servers` of lua/config/languages.lua, the same
# table the configuration hands to mason-lspconfig, so it is kept in one place.
#
# Mason's installers run whatever the server is published with: npm for
# pyright/bashls/jsonls/vimls, a Python venv, cargo, a JDK for jdtls, plus
# unzip/tar/gzip for release archives. Those runtimes are this package's
# dependencies.

mpkg_inherit pkgcommon

MPKG_TITLE="Mason"
MPKG_DESC="The language servers the Neovim configuration lists, installed through mason.nvim"
MPKG_HOMEPAGE="https://github.com/mason-org/mason.nvim"
MPKG_KIND="config"
MPKG_UNVERSIONED=1
MPKG_PROBE_CMD=""
MPKG_DEPENDS=(nvim-config nodejs uv rust jdk curl git)
MPKG_REQUIRES_CMD=(unzip tar gzip)

MPKG_NVIM_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/nvim"

mpkg_run() {
    local plugins servers
    command -v nvim >/dev/null 2>&1 || { mpkg::err "nvim is not on PATH"; return 1; }

    # Where lazy.nvim keeps the plugins.
    plugins="$(nvim --headless --clean +'lua io.write(vim.fn.stdpath("data"))' +qa 2>/dev/null)/lazy"
    [[ -d "${plugins}/mason.nvim" && -d "${plugins}/mason-lspconfig.nvim" ]] \
        || { mpkg::err "mason.nvim is not in ${plugins}; run 'mpkg install --force nvim-config'"; return 1; }

    servers="$(mpkg::mason_servers)"
    if [[ -z "${servers}" ]]; then
        mpkg::warn "no servers in lua/config/languages.lua; nothing to install"
    else
        mpkg::step "installing language servers: ${servers}"
        # shellcheck disable=SC2086  # one word per server
        if ! mpkg::mason_install "${plugins}" ${servers}; then
            mpkg::stage_failed "${MPKG_NAME}: :MasonInstall failed"
            return 1
        fi
    fi
    mpkg_cleanup

    MPKG_VERSION="present"
    MPKG_DEST_NAME=""
    MPKG_STATUS="installed"
}

# lspconfig names from the `servers` of lua/config/languages.lua. The installed
# copy wins, since that is what nvim actually runs.
mpkg::mason_servers() {
    local langs="${MPKG_NVIM_DIR}/lua/config/languages.lua"
    [[ -r "${langs}" ]] || langs="${MPKG_ROOT}/nvim/lua/config/languages.lua"
    [[ -r "${langs}" ]] || return 0
    local script="${MPKG_WORK}/mason-servers.lua"
    MPKG_TMPFILES+=(mason-servers.lua)
    printf '%s\n' "io.write(table.concat(dofile(arg[1]).servers or {}, ' '))" > "${script}"
    nvim --clean -l "${script}" "${langs}" 2>/dev/null
}

# :MasonInstall blocks in a headless nvim and exits non-zero if any package
# fails. It is run with --clean and only the two plugins on the runtimepath, so
# that the configuration's own setup does not start the same installs in the
# background.
mpkg::mason_install() {
    local plugins="$1"; shift
    local script="${MPKG_WORK}/mason-install.lua"
    MPKG_TMPFILES+=(mason-install.lua)
    cat > "${script}" <<'LUA'
local servers = vim.split(os.getenv('MPKG_MASON_SERVERS'), ' ', { trimempty = true })
require('mason').setup()
local registry = require('mason-registry')
registry.refresh()
local map = require('mason-lspconfig').get_mappings().lspconfig_to_package
local pkgs = {}
for _, s in ipairs(servers) do
    local name = map[s] or s
    -- :MasonInstall rejects the whole list over one unknown name.
    if registry.has_package(name) then
        table.insert(pkgs, name)
    else
        io.stdout:write('mpkg-mason-skip ' .. s .. '\n')
    end
end
if #pkgs == 0 then return end
-- --quiet: installer stderr (npm warnings) echoed through nvim_err_write
-- raises in a headless nvim and aborts this script midway. What counts is
-- whether each package ended up installed, so check that directly.
pcall(vim.cmd, 'MasonInstall --quiet ' .. table.concat(pkgs, ' '))
local failed = {}
for _, name in ipairs(pkgs) do
    if not registry.get_package(name):is_installed() then table.insert(failed, name) end
end
if #failed > 0 then
    io.stdout:write('mpkg-mason-failed ' .. table.concat(failed, ' ') .. '\n')
    vim.cmd('cquit 1')
end
LUA
    MPKG_MASON_SERVERS="$*" mpkg::run nvim --headless --clean \
        --cmd "set runtimepath^=${plugins}/mason.nvim,${plugins}/mason-lspconfig.nvim" \
        +"luafile ${script}" +qa
    local rc=$? s
    for s in $(sed -n 's/.*mpkg-mason-skip \([^ ]*\).*/\1/p' "${MPKG_LOG}"); do
        mpkg::warn "${s} has no Mason package; skipped"
    done
    s="$(sed -n 's/.*mpkg-mason-failed //p' "${MPKG_LOG}")"
    [[ -n "${s}" ]] && mpkg::err "not installed: ${s}"
    return "${rc}"
}

mpkg_link() { return 0; }

mpkg_remove() {
    mpkg::warn "leaving the servers in place; remove them with :Mason inside nvim"
}
