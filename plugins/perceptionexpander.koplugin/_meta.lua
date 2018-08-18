local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local PerceptionExpander = WidgetContainer:new{
    name = "perceptionexpander",
    fullname = _("Perception expander"),
    description = _([[Improves your reading speed with the help of two vertical lines over the text.]]),
}

return PerceptionExpander
