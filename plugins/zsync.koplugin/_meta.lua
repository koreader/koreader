local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local ZSync = WidgetContainer:new{
    name = "zsync",
    fullname = _("Zsync"),
    description = _([[Devices in the same Wi-Fi network can transfer documents between each other directly.]]),
}

return ZSync
