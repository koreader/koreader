local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local ReadTimer = WidgetContainer:new{
    name = "readtimer",
    fullname = _("Read timer"),
    description = _([[Shows an alarm after a specified amount of time.]]),
}
return ReadTimer

