-- Neovim configuration (requires Neovim 0.12+).
--
--   lua/config/options.lua    editor settings
--   lua/config/keymaps.lua    global keymaps (plugin keys live with their plugin)
--   lua/config/autocmds.lua   autocommands and filetype detection
--   lua/config/lsp.lua        LspAttach keymaps, diagnostics, per-server settings
--   lua/config/languages.lua  tree-sitter parsers and language servers to install
--   lua/config/lazy.lua       lazy.nvim bootstrap
--   lua/config/loader.lua     feature modules: discovery, on/off/drop, :Module
--   lua/config/modules.lua    which modules are on (one machine: :Module)
--   lua/plugins/*.lua         core plugin specs, one file per area
--   lua/modules/*.lua         feature modules, one file per feature

vim.g.mapleader = '\\'
vim.g.maplocalleader = '\\'

require('config.options')
require('config.keymaps')
require('config.autocmds')
require('config.lazy')
require('config.lsp')
