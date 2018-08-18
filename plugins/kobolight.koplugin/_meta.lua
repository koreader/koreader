local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local KoboLight = WidgetContainer:new{
    name = 'kobolight',
    fullname = _("Frontlight gesture controller"),
    description = _([[Controls the frontlight with gestures on the left border of screen.]]),
}

return KoboLight
