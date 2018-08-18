local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local AutoSuspendWidget = WidgetContainer:new{
    name = "autosuspend",
    fullname = _("Auto suspend"),
    description = _([[Suspends the device after a period of inactivity.]]),
}

return AutoSuspendWidget
