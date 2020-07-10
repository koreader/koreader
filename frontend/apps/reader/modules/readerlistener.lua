local BD = require("ui/bidi")
local EventListener = require("ui/widget/eventlistener")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local ReaderListener = EventListener:new{}

function ReaderListener:onToggleReadingOrder()
    local document_module = self.ui.document.info.has_pages and self.ui.paging or self.ui.rolling
    document_module.inverse_reading_order = not document_module.inverse_reading_order
    document_module:setupTouchZones()
    local is_rtl = BD.mirroredUILayout()
    if document_module.inverse_reading_order then
        is_rtl = not is_rtl
    end
    UIManager:show(Notification:new{
        text = is_rtl and _("RTL page turning.") or _("LTR page turning."),
        timeout = 2.5,
    })
    return true
end


return ReaderListener
