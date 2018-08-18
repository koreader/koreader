local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local AutoFrontlightWidget = WidgetContainer:new{
    name = "autofrontlight",
    fullname = _("Auto frontlight"),
    description = _([[Automatically turns the frontlight on and off once brightness in the environment reaches a certain level.]]),
}

return AutoFrontlightWidget
