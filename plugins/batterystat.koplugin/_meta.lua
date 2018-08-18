local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local BatteryStatWidget = WidgetContainer:new{
    name = "batterystat",
    fullname = _("Battery statistics"),
    description = _([[Collects and displays battery statistics.]]),
}

return BatteryStatWidget
