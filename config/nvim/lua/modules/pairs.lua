return {
    desc = 'Auto-close brackets and quotes (mini.pairs)',
    plugins = {
        { 'nvim-mini/mini.pairs', event = 'InsertEnter', opts = {} },
    },
}
