local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local PerceptionExpander = WidgetContainer:new{
    is_enabled = nil,
    name = "perceptionexpander",
    fullname = _("Perception expander"),
}

return PerceptionExpander
