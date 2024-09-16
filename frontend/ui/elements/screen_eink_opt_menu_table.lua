local Device = require("device")
local _ = require("gettext")
local Screen = Device.screen

local eink_settings_table = {
    text = _("E-ink settings"),
    sub_item_table = {
        {
            text = _("Use smaller panning rate"),
            checked_func = function() return Screen.low_pan_rate end,
            callback = function()
                Screen.low_pan_rate = not Screen.low_pan_rate
                G_reader_settings:saveSetting("low_pan_rate", Screen.low_pan_rate)
            end,
        },
        dofile("frontend/ui/elements/flash_ui.lua"),
        dofile("frontend/ui/elements/flash_keyboard.lua"),
        {
            text = _("Avoid mandatory black flashes in UI"),
            checked_func = function() return G_reader_settings:isTrue("avoid_flashing_ui") end,
            callback = function()
                G_reader_settings:flipNilOrFalse("avoid_flashing_ui")
            end,
        },
    },
}

if Device:hasEinkScreen() then
    table.insert(eink_settings_table.sub_item_table, 1, dofile("frontend/ui/elements/refresh_menu_table.lua"))
    if (Screen.wf_level_max or 0) > 0 then
        table.insert(eink_settings_table.sub_item_table, dofile("frontend/ui/elements/waveform_level.lua"))
    end
end

return eink_settings_table
