local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local CoverBrowser = WidgetContainer:new{
    name = "coverbrowser",
    fullname = _("Cover browser"),
    description = _([[Alternative display modes for file browser and history.]]),
}

return CoverBrowser
