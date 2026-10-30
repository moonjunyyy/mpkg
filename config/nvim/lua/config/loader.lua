-- Feature modules: one file per feature in lua/modules/. The directory is
-- scanned, so a new file is a new module; nothing else to register. A module
-- returns
--
--   {
--       desc    = 'one line, shown by :Module',
--       default = true,              -- true | 'off' | false; true if left out
--       plugins = { ... },           -- its own lazy.nvim specs
--       extend  = { <point> = ... }, -- what it adds to core plugins (M.points)
--   }
--
-- A module is on (loaded), off (its plugins stay installed but are not
-- loaded: lazy's `cond`) or drop (left out of the spec, so :Lazy clean removes
-- its plugins). Later wins: the module's `default`, config/modules.lua (this
-- repository), the state file :Module writes for this machine. That file is in
-- stdpath('state'), not here: mpkg replaces the configuration directory on
-- upgrade, and treats a directory edited in place as no longer its own.
local M = {}

M.state_file = vim.fs.joinpath(vim.fn.stdpath('state'), 'modules')
M.servers = {} -- extend.servers of the modules that are on; config/lsp.lua enables them
M.started = {} -- name -> state this session started with

local STATES = { [true] = 'on', on = 'on', off = 'off', [false] = 'drop', drop = 'drop' }
local ACTIONS = { 'list', 'on', 'off', 'drop', 'reset' }

-- Extension points. Plugin options have no common shape -- every plugin has
-- its own, and those stay in the module's `plugins` as they are -- but what a
-- feature adds to the shared machinery does. A module names a point and gives
-- a value; the point turns it into a spec that lazy.nvim merges into the core
-- plugin (or, for servers, hands it to config/lsp.lua). A new point is one
-- entry here.
M.points = {
    -- tree-sitter parsers to install: { 'name', ... }
    parsers = function(v)
        return { 'nvim-treesitter/nvim-treesitter', optional = true, opts = { parsers = v } }
    end,
    -- conform formatters: { filetype = { 'formatter', ... } }
    formatters = function(v)
        return { 'stevearc/conform.nvim', optional = true, opts = { formatters_by_ft = v } }
    end,
    -- blink.cmp sources: { id = <provider config> }, appended to the default list
    sources = function(v)
        local ids = vim.tbl_keys(v)
        table.sort(ids)
        return { 'saghen/blink.cmp', optional = true, opts = { sources = { default = ids, providers = v } } }
    end,
    -- which-key entries: { { '<leader>x', group = 'name' }, ... }
    groups = function(v)
        return { 'folke/which-key.nvim', optional = true, opts = { spec = v } }
    end,
    -- language servers: { name = <vim.lsp.Config> }; the binary comes from the
    -- module's own toolchain, not from Mason
    servers = function(v)
        M.servers = vim.tbl_extend('force', M.servers, v)
    end,
}

local function read_state()
    local state = {}
    local ok, lines = pcall(vim.fn.readfile, M.state_file)
    for _, line in ipairs(ok and lines or {}) do
        local name, value = line:match('^%s*([%w_.-]+)%s+(%a+)%s*$')
        if name and STATES[value] then
            state[name] = value
        end
    end
    return state
end

local function write_state(state)
    local lines = {}
    for name, value in vim.spairs(state) do
        lines[#lines + 1] = name .. ' ' .. value
    end
    vim.fn.mkdir(vim.fs.dirname(M.state_file), 'p')
    vim.fn.writefile(lines, M.state_file)
end

local function load(name)
    local ok, mod = pcall(require, 'modules.' .. name)
    if ok and type(mod) == 'table' then
        return mod
    end
    vim.notify(('module %s: %s'):format(name, ok and 'does not return a table' or mod), vim.log.levels.ERROR)
end

-- Every module with the state it is set to now, sorted by name.
function M.list()
    local ok, repo = pcall(require, 'config.modules')
    repo = ok and type(repo) == 'table' and repo or {}
    local state = read_state()
    local dir = vim.fs.joinpath(vim.fn.stdpath('config'), 'lua', 'modules')
    local out = {}
    if not vim.uv.fs_stat(dir) then
        return out
    end
    for file, kind in vim.fs.dir(dir) do
        local name = kind == 'file' and file:match('^(.+)%.lua$')
        local mod = name and load(name)
        if mod then
            local want = state[name]
            if want == nil then want = repo[name] end
            if want == nil then want = mod.default end
            if want == nil then want = true end
            out[#out + 1] = { name = name, mod = mod, state = STATES[want] or 'on' }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- The lazy.nvim specs of the modules that are not dropped.
function M.spec()
    local specs = {}
    for _, m in ipairs(M.list()) do
        M.started[m.name] = m.state
        if m.state ~= 'drop' then
            for _, p in ipairs(m.mod.plugins or {}) do
                local s = type(p) == 'string' and { p } or vim.deepcopy(p)
                if m.state == 'off' then
                    s.cond = false
                end
                specs[#specs + 1] = s
            end
            -- An 'off' module adds nothing: what it extends would point at
            -- plugins that are not loaded.
            if m.state == 'on' then
                for point, value in pairs(m.mod.extend or {}) do
                    local to = M.points[point]
                    if to then
                        specs[#specs + 1] = to(value)
                    else
                        vim.notify(('module %s: no extension point %q'):format(m.name, point), vim.log.levels.WARN)
                    end
                end
            end
        end
    end
    return specs
end

local function show()
    local lines = {}
    for _, m in ipairs(M.list()) do
        local was, now = M.started[m.name], m.state
        local note = ''
        if was == nil then
            note = '  [new: next start]'
        elseif was ~= now then
            note = ('  [%s -> %s at next start]'):format(was, now)
        end
        lines[#lines + 1] = ('%-10s %-4s  %s%s'):format(m.name, now, m.mod.desc or '', note)
    end
    vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO, { title = 'Modules' })
end

-- :Module                         list modules and their state
-- :Module on|off|drop {name}      set it for this machine (next start)
-- :Module reset {name}            back to config/modules.lua
function M.command()
    vim.api.nvim_create_user_command('Module', function(a)
        local action, name = a.fargs[1] or 'list', a.fargs[2]
        if action == 'list' then
            return show()
        end
        if not vim.list_contains(ACTIONS, action) or not name then
            return vim.notify('usage: :Module [list] | :Module on|off|drop|reset {name}', vim.log.levels.ERROR)
        end
        if not vim.iter(M.list()):any(function(m) return m.name == name end) then
            return vim.notify(('no module %s in lua/modules/'):format(name), vim.log.levels.ERROR)
        end
        local state = read_state()
        state[name] = action ~= 'reset' and action or nil
        write_state(state)
        show()
        if action == 'drop' then
            vim.notify(('%s: after the restart, :Lazy clean removes its plugins'):format(name))
        end
    end, {
        nargs = '*',
        desc = 'List feature modules, or set one on/off/drop on this machine',
        complete = function(lead, line)
            local before = vim.split(line:sub(1, #line - #lead), '%s+', { trimempty = true })
            local items = #before <= 1 and ACTIONS
                or vim.tbl_map(function(m) return m.name end, M.list())
            return vim.tbl_filter(function(s) return vim.startswith(s, lead) end, items)
        end,
    })
end

return M
