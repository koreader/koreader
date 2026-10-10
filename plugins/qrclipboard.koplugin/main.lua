--[[--
This plugin generates a QR code from clipboard content.

@module koplugin.QRClipboard
--]]--

local Device = require("device")
local Dispatcher = require("dispatcher")
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
        self:onDispatcherRegisterActions()
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
                local text
                if this.ui.rolling then
                    local extended_text =
                        this.document:extendXPointersToSentenceSegment(this.selected_text.pos0, this.selected_text.pos1)
                    text = extended_text and extended_text.text
                end
                text = util.cleanupSelectedText(text or this.selected_text.text)
                if Device:hasClipboard() then -- let the text to be reused via menu
                    Device.input.setClipboardText(text)
                end
                UIManager:show(QRMessage:new{
                    text = text,
                    invert_bidi = this.ui.view:shouldInvertBiDiLayoutMirroring(),
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
            self:onQRFromClipboard()
        end,
    }
end

function QRClipboard:onQRFromClipboard()
    local clipboard_text = Device.input.getClipboardText()
    if not clipboard_text or clipboard_text == "" then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = _("Clipboard is empty") })
        return nil
    end
    local invert_bidi = self.ui and self.ui.view and self.ui.view:shouldInvertBiDiLayoutMirroring()
    UIManager:show(QRMessage:new{
        text = clipboard_text,
        invert_bidi = invert_bidi,
    })
end

function QRClipboard:onDispatcherRegisterActions()
    Dispatcher:registerAction("qr_from_clipboard", {
        category = "none",
        event = "QRFromClipboard",
        title = _("Generate QR code from clipboard"),
        general = true
    })
end

return QRClipboard
