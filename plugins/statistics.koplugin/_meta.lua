local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local ReaderStatistics = WidgetContainer:new{
    name = "statistics",
    fullname = _("Reader statistics"),
    description = _([[Keeps and displays your reading statistics.]]),
}

return ReaderStatistics
