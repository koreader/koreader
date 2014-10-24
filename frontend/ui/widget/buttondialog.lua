local ButtonTable = require("ui/widget/buttontable")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("ui/device")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local Input = require("ui/input")
local Screen = require("ui/screen")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")

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
            bordersize = 2,
            radius = 7,
            padding = 2,
        }
    }
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

return ButtonDialog
