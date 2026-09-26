-- Neovim configuration (requires Neovim 0.11+).
--
--   lua/config/options.lua    editor settings
--   lua/config/keymaps.lua    global keymaps (plugin keys live with their plugin)
--   lua/config/autocmds.lua   autocommands and filetype detection
--   lua/config/lsp.lua        LspAttach keymaps, diagnostics, per-server settings
--   lua/config/languages.lua  tree-sitter parsers and language servers to install
--   lua/config/lazy.lua       lazy.nvim bootstrap
--   lua/plugins/*.lua         plugin specs, one file per area

vim.g.mapleader = '\\'
vim.g.maplocalleader = '\\'

require('config.options')
require('config.keymaps')
require('config.autocmds')
require('config.lazy')
require('config.lsp')
