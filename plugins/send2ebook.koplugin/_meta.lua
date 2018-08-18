local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Send2Ebook = WidgetContainer:new{
    name = "send2ebook",
    fullname = _("Send to eBook"),
    description = _([[Receives articles sent with the Send2Ebook PC/Android application.]]),
}

return Send2Ebook
