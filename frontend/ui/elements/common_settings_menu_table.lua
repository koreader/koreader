local Device = require("device")
local Language = require("ui/language")
local NetworkMgr = require("ui/networkmgr")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local _ = require("gettext")

local common_settings = {}

if Device:hasFrontlight() then
    local ReaderFrontLight = require("apps/reader/modules/readerfrontlight")
    table.insert(common_settings, {
        text = _("Frontlight"),
        callback = function()
            ReaderFrontLight:onShowFlDialog()
        end,
    })
end

table.insert(common_settings, {
    text = _("Night mode"),
    checked_func = function() return G_reader_settings:readSetting("night_mode") end,
    callback = function()
        local night_mode = G_reader_settings:readSetting("night_mode") or false
        Screen:toggleNightMode()
        G_reader_settings:saveSetting("night_mode", not night_mode)
    end
})
table.insert(common_settings, {
    text = _("Network"),
    sub_item_table = {
        NetworkMgr:getWifiMenuTable(),
        NetworkMgr:getProxyMenuTable(),
    }
})
table.insert(common_settings, {
    text = _("Screen"),
    sub_item_table = {
        require("ui/elements/screen_dpi_menu_table"),
        require("ui/elements/screen_eink_opt_menu_table"),
        require("ui/elements/refresh_menu_table"),
    },
})
table.insert(common_settings, Language:getLangMenuTable())
table.insert(common_settings, {
    text = _("Show advanced options"),
    checked_func = function() return G_reader_settings:readSetting("show_advanced") end,
    callback = function()
        local show_advanced = G_reader_settings:readSetting("show_advanced") or false
        G_reader_settings:saveSetting("show_advanced", not show_advanced)
    end
})

return common_settings
