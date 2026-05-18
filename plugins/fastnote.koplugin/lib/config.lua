--[[--
lib/config.lua — fastnote.koplugin user configuration loader.

Reads a Lua-table config file and merges it with built-in defaults.
Pure Lua; no KOReader runtime dependencies — fully busted-testable.

The config file (typically koreader/settings/fastnote.conf) must be a
plain Lua file that returns a table, e.g.:

    return {
        finger_draw = false,
    }

Any key absent from the file is filled from Config.DEFAULTS.
Syntax errors or non-table returns fall back to DEFAULTS silently.

@module fastnote.config
--]]--

local Config = {}

--- Default values for all supported config keys.
-- These apply when a key is absent from the user's config file.
Config.DEFAULTS = {
    --- Allow drawing with finger touches in addition to the pen.
    -- false = pen-only (default). true = pen + finger both draw.
    finger_draw = false,
}

--- Load a config file and return the merged result.
-- @param  path  absolute path to the config file, or nil to use defaults only.
-- @return table  config with every key guaranteed to be present (from file or DEFAULTS).
function Config.load(path)
    local cfg = {}

    if path ~= nil then
        local chunk, _err = loadfile(path)
        if chunk then
            local ok, result = pcall(chunk)
            if ok and type(result) == "table" then
                cfg = result
            end
        end
    end

    -- Merge defaults for any key absent from the file.
    -- We copy into a fresh table so mutations by the caller cannot affect DEFAULTS.
    local out = {}
    for k, v in pairs(Config.DEFAULTS) do
        out[k] = (cfg[k] ~= nil) and cfg[k] or v
    end

    return out
end

return Config
