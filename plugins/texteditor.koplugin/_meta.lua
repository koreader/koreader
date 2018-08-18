local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local TextEditor = WidgetContainer:new{
    name = "texteditor",
    fullname = _("Text editor"),
    description = _([[A basic text editor for making small changes to plain text files.]]),
}

return TextEditor
