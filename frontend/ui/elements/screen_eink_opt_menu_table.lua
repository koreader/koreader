local _ = require("gettext")
local Screen = require("device").screen

local eink = G_reader_settings:readSetting("eink")
Screen.eink = (eink == nil) and true or eink

return {
    text = _("E-ink optimization"),
    checked_func = function() return Screen.eink end,
    callback = function()
        Screen.eink = not Screen.eink
        G_reader_settings:saveSetting("eink", Screen.eink)
    end,
}
