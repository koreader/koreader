--[[
Centralizes migration concerns for LuaSettings & DocSettings
--]]

local DocSettings = require("docsettings")
local LuaSettings = require("luasettings")
local logger = require("logger")

local SettingsMigration = {}

-- Shockingly, handles settings migration
-- NOTE: supports LuaSettings & DocSettings objects as input, as both implement the same API
function SettingsMigration:migrateSettings(config)
    -- Figure out what kind of object we were passed, to make the logging more precise
    local cfg_mt_idx = getmetatable(config).__index
    local cfg_class
    if cfg_mt_idx == DocSettings then
        cfg_class = "book"
    elseif cfg_mt_idx == LuaSettings then
        cfg_class = "global"
    else
        -- Input object isn't a supported *Settings class, warn & abort instead of going kablooey.
        logger.warn("Passed an unsupported object class to SettingsMigration!")
        return
    end

    -- Fine-grained CRe margins (#4945)
    local old_margins = config:readSetting("copt_page_margins")
    if old_margins then
        logger.info("Migrating old", cfg_class, "CRe margin settings: L", old_margins[1], "T", old_margins[2], "R", old_margins[3], "B", old_margins[4])
        -- Format was: {left, top, right, bottom}
        config:saveSetting("copt_h_page_margins", {old_margins[1], old_margins[3]})
        config:saveSetting("copt_t_page_margin", old_margins[2])
        config:saveSetting("copt_b_page_margin", old_margins[4])
        -- Wipe it
        config:delSetting("copt_page_margins")
    end
end

return SettingsMigration
