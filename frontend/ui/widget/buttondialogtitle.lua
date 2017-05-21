local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local UIManager = require("ui/uimanager")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen

local ButtonDialogTitle = InputContainer:new{
    title = nil,
    title_align = nil,
    buttons = nil,
    tap_close_callback = nil,
}

function ButtonDialogTitle:init()
    self.medium_font_face = Font:getFace("ffont")
    self.large_font_face = Font:getFace("largeffont")
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close button dialog" }
        }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                }
            }
        }
    end
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        FrameContainer:new{
            VerticalGroup:new{
                align = "center",
                VerticalSpan:new{ width = 2 },
                TextBoxWidget:new{
                    text = self.title,
                    width = Screen:getWidth() * 0.8 ,
                    face = self.medium_font_face,
                    bold = true,
                    alignment = self.title_align or "left",
                },
                VerticalSpan:new{ width = 2 },
                LineWidget:new{
                    dimen = Geom:new{
                        w = Screen:getWidth() * 0.9,
                        h = 1,
                    }
                },
                VerticalSpan:new{ width = 2 },
                ButtonTable:new{
                    width = Screen:getWidth() * 0.9,
                    buttons = self.buttons,
                    show_parent = self,
                },
            },
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 2,
            radius = 7,
            padding = 2,
        }
    }
end

function ButtonDialogTitle:onShow()
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen
    end)
end

function ButtonDialogTitle:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self[1][1].dimen
    end)
end

function ButtonDialogTitle:onTapClose()
    UIManager:close(self)
    if self.tap_close_callback then
        self.tap_close_callback()
    end
    return true
end

function ButtonDialogTitle:onClose()
    self:onTapClose()
    return true
end

function ButtonDialogTitle:paintTo(...)
    InputContainer.paintTo(self, ...)
    self.dimen = self[1][1].dimen -- FrameContainer
end

return ButtonDialogTitle
