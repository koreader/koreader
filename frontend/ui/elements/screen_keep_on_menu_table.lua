local isAndroid, android = pcall(require, "android")
local _ = require("gettext")

if not isAndroid then return end

local function isWakeLock()
    return not G_reader_settings:isTrue("disable_android_wakelock")
end

local function setWakeLock(enable)
    G_reader_settings:saveSetting("disable_android_wakelock", not enable)
end

return {
    text = _("Keep screen on"),
    checked_func = function()
        return isWakeLock()
    end,
    callback = function()
        local current = isWakeLock()
        android.setWakeLock(not current)
        setWakeLock(not current)
    end,
}
