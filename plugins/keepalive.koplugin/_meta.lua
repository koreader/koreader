local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local KeepAlive = WidgetContainer:new{
    name = "keepalive",
    fullname = _("Keep alive"),
    description = _([[Keeps the device awake to prevent automatic Wi-Fi disconnects.]]),
}

return KeepAlive
