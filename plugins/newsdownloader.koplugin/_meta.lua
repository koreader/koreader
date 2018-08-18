local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local NewsDownloader = WidgetContainer:new{
    name = "newsdownloader",
    fullname = _("News downloader"),
    description = _([[Retrieves RSS and Atom news entries and saves them as HTML files.]]),
}

return NewsDownloader
