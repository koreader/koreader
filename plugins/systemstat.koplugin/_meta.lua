local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local SystemStatWidget = WidgetContainer:new{
    name = "systemstat",
    fullname = _("System statistics"),
    description = _([[Shows system statistics.]]),
}

return SystemStatWidget
