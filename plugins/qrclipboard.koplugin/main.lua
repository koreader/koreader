--[[--
This plugin generates a QR code from clipboard content.

@module koplugin.QRClipboard
--]]--

local Device = require("device")
local QRMessage = require("ui/widget/qrmessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")

local QRClipboard = WidgetContainer:extend{
    name = "qrclipboard",
    is_doc_only = false,
}

function QRClipboard:init()
    self.ui.menu:registerToMainMenu(self)
    if self.ui.highlight then
        self:addToHighlightDialog()
    end
end

function QRClipboard:addToHighlightDialog()
    -- 12_search is the last item in the highlight dialog. We want to sneak in the 'Generate QR code' item
    -- second to last, thus name '12_generate' so the alphabetical sort keeps '12_search' last.
    self.ui.highlight:addToHighlightDialog("12_generate_qr_code", function(this)
        return {
            text = _("Generate QR code"),
            enabled = Device:hasClipboard(),
            callback = function()
                Device.input.setClipboardText(util.cleanupSelectedText(this.selected_text.text))
                UIManager:show(QRMessage:new{
                    text = Device.input.getClipboardText(),
                    width = Device.screen:getWidth(),
                    height = Device.screen:getHeight()
                })
                this:onClose()
            end,
        }
    end)
end

function QRClipboard:addToMainMenu(menu_items)
    menu_items.qrclipboard = {
        text = _("QR from clipboard"),
        callback = function()
            UIManager:show(QRMessage:new{
                text = Device.input.getClipboardText(),
                width = Device.screen:getWidth(),
                height = Device.screen:getHeight()
            })
        end,
    }
end

return QRClipboard
