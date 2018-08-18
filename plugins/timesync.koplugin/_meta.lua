local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local TimeSync = WidgetContainer:new{
    name = "timesync",
    fullname = _("Time sync"),
    description = _([[Synchronizes the device time with NTP servers.]]),
}

return TimeSync
