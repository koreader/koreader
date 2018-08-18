local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local EvernoteExporter = WidgetContainer:new{
    name = "evernote",
    fullname = _("Evernote"),
    description = _([[Exports hightlights and notes to the Evernote cloud.]]),
}

return EvernoteExporter
