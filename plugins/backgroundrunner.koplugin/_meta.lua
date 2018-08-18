local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local BackgroundRunnerWidget = WidgetContainer:new{
    name = "backgroundrunner",
    fullname = _("Background runner"),
    description = _([[Service to other plugins: allows tasks to run regularly in the background.]]),
}
return BackgroundRunnerWidget
