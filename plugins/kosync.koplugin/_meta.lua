local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local KOSync = WidgetContainer:new{
    name = "kosync",
    fullname = _("Progress sync"),
    description = _([[Synchronizes your reading progess to a server across your KOReader devices.]]),
}

return KOSync
