local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Screen = require("device").screen

local ButtonDialog = InputContainer:new{
    buttons = nil,
    tap_close_callback = nil,
}

function ButtonDialog:init()
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
            ButtonTable:new{
                width = Screen:getWidth()*0.9,
                buttons = self.buttons,
                show_parent = self,
            },
            background = Blitbuffer.COLOR_WHITE,
            bordersize = Screen:scaleBySize(2),
            radius = Screen:scaleBySize(7),
            padding = Screen:scaleBySize(2),
        }
    }
end

function ButtonDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen
    end)
end

function ButtonDialog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self[1][1].dimen
    end)
end

function ButtonDialog:onTapClose()
    UIManager:close(self)
    if self.tap_close_callback then
        self.tap_close_callback()
    end
    return true
end

function ButtonDialog:onClose()
    self:onTapClose()
    return true
end

function ButtonDialog:paintTo(...)
    InputContainer.paintTo(self, ...)
    self.dimen = self[1][1].dimen -- FrameContainer
end

return ButtonDialog
