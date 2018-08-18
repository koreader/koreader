local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local SSH = WidgetContainer:new{
    name = 'SSH',
    fullname = _("SSH"),
    description = _([[Connect and transfer files to the device using SSH.]]),
}

return SSH
