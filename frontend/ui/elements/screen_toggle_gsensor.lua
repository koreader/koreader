local Device = require("device")
local _ = require("gettext")

return {
    text = _("Ignore accelerometer rotation events"),
    checked_func = function()
        return G_reader_settings:isTrue("input_ignore_gsensor")
    end,
    callback = function()
        G_reader_settings:flipNilOrFalse("input_ignore_gsensor")
        Device:toggleGSensor()
    end,
}
