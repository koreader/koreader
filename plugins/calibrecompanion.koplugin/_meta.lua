local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local CalibreCompanion = WidgetContainer:new{
    name = "calibrecompanion",
    fullname = _("Calibre companion"),
    description = _([[Send documents from calibre library directly to device via Wi-Fi connection]]),
}

return CalibreCompanion
