local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Hello = WidgetContainer:new{
    name = 'hello',
    fullname = _("Hello"),
    description = _([[This is a debugging plugin.]]),
    is_doc_only = false,
}

return Hello
