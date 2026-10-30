-- The feature modules this configuration uses: lua/modules/<name>.lua.
--
--   'on'    loaded
--   'off'   plugins installed but not loaded
--   'drop'  left out; :Lazy clean then removes its plugins
--
-- A module not listed here takes its own `default` (on unless it says
-- otherwise), so adding a feature is adding its file. On one machine,
-- :Module on|off|drop|reset {name} overrides this table without editing it,
-- and :Module lists what is in effect.
return {
    copilot   = 'on',
    filetree  = 'on',
    git       = 'on',
    lean      = 'on',
    markview  = 'on',
    outline   = 'on',
    pairs     = 'on',
    telescope = 'on',
}
