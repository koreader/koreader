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
}

function QRClipboard:init()
    if self.document then
        self:addToHighlightDialog()
    end
    if Device:hasClipboard() then
        self.ui.menu:registerToMainMenu(self)
    end
end

function QRClipboard:addToHighlightDialog()
    -- 12_search is the last item in the highlight dialog. We want to sneak in the 'Generate QR code' item
    -- second to last, thus name '12_generate' so the alphabetical sort keeps '12_search' last.
    self.ui.highlight:addToHighlightDialog("12_generate_qr_code", function(this)
        return {
            text = _("Generate QR code"),
            callback = function()
                -- 'this' is self.ui.highlight. Do as ReaderHighlight:saveHighlight() does.
                this:highlightFromHoldPos()
                if not (this.selected_text and this.selected_text.pos0 and this.selected_text.pos1) then return end
                local text = this.ui.rolling
                    and this.document:extendXPointersToSentenceSegment(this.selected_text.pos0, this.selected_text.pos1)
                text = util.cleanupSelectedText(text or this.selected_text.text)
                if Device:hasClipboard() then -- let the text to be reused via menu
                    Device.input.setClipboardText(text)
                end
                UIManager:show(QRMessage:new{
                    text = text,
                    width = Device.screen:getWidth(),
                    height = Device.screen:getHeight(),
                    dismiss_callback = function()
                        -- delay clearing highlighted text a bit, so the user can see
                        -- what was used to generate the QR code
                        UIManager:scheduleIn(G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S"), function()
                            this:clear()
                        end)
                    end,
                })
                this:onClose(true)
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
                height = Device.screen:getHeight(),
            })
        end,
    }
end

return QRClipboard
