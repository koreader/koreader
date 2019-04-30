--[[
Centralizes migration concerns for LuaSettings & DocSettings
--]]

local logger = require("logger")

local SettingsMigration = {}

-- Handles migration of per-document settings
-- NOTE: supports LuaSettings & DocSettings objects as input, as both implement the same API
function SettingsMigration:migrateSettings(config)
    -- Fine-grained CRe margins (#4945)
    local old_margins = config:readSetting("copt_page_margins")
    if old_margins then
        logger.info("Migrating old CRe margin settings: L", old_margins[1], "T", old_margins[2], "R", old_margins[3], "B", old_margins[4])
        -- Format was: {left, top, right, bottom}
        config:saveSetting("copt_h_page_margins", {old_margins[1], old_margins[3]})
        config:saveSetting("copt_t_page_margin", old_margins[2])
        config:saveSetting("copt_b_page_margin", old_margins[4])
        -- Wipe it
        config:delSetting("copt_page_margins")
    end
end

return SettingsMigration
