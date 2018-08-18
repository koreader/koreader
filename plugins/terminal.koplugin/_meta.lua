local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Terminal = WidgetContainer:new{
    name = "terminal",
    fullname = _("Terminal"),
    description = _([[Executes simple commands and shows their output.]]),
}

return Terminal
