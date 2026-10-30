return {
    desc = 'Rendered markdown in the buffer (markview)',
    plugins = {
        {
            'OXY2DEV/markview.nvim',
            -- Not lazy-loaded: markview defers its own work, and loading it on
            -- FileType sometimes missed the first markdown buffer (upstream advice).
            lazy = false,
            config = function()
                local presets = require('markview.presets')
                require('markview').setup({
                    markdown = { headings = presets.headings.slanted },
                    preview = { icon_provider = 'devicons' },
                })
            end,
        },
    },
}
