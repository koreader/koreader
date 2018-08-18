local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Goodreads = WidgetContainer:new {
    name = "goodreads",
    fullname = _("Goodreads"),
    description = _([[Allows browsing and searching the Goodreads database of books.]]),
}

return Goodreads
