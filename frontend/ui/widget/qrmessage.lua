--[[--
Widget that displays a qr code.

It vanishes on key press or after a given timeout.

Example:
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    local Screen = require("device").screen
    local sample
    sample = QRMessage:new{
        text = _("my message"),
        height = Screen:scaleBySize(400),
        width = Screen:scaleBySize(400),
        timeout = 5,  -- This widget will vanish in 5 seconds.
    }
    UIManager:show(sample)
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local QRWidget = require("ui/widget/qrwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local Input = Device.input
local Screen = Device.screen

local QRMessage = InputContainer:new{
    modal = true,
    timeout = nil, -- in seconds
    text = nil,  -- The text to encode.
    width = nil,  -- The width. Keep it nil to use original width.
    height = nil,  -- The height. Keep it nil to use original height.
    dismiss_callback = function() end,
    alpha = nil,
    scale_factor = 0,
}

function QRMessage:init()
    if Device:hasKeys() then
        self.key_events = {
            AnyKeyPressed = { { Input.group.Any },
                seqtext = "any key", doc = "close dialog" }
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

    local image_widget = QRWidget:new{
        text = self.text,
        width = self.width and math.floor(0.9 * self.width),
        height = self.height and math.floor(0.9 * self.height),
        alpha = self.alpha,
        scale_factor = self.scale_factor,
    }

    local width = self.width or Screen:getWidth()
    local height = self.height or Screen:getHeight()

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        padding = math.floor(0.05 * math.min(width, height)),
        image_widget,
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        frame,
    }
end

function QRMessage:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self[1][1].dimen
    end)
    return true
end

function QRMessage:onShow()
    -- triggered by the UIManager after we got successfully shown (not yet painted)
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen
    end)
    if self.timeout then
        UIManager:scheduleIn(self.timeout, function() UIManager:close(self) end)
    end
    return true
end

function QRMessage:onAnyKeyPressed()
    -- triggered by our defined key events
    self.dismiss_callback()
    UIManager:close(self)
    if self.readonly ~= true then
        return true
    end
end

function QRMessage:onTapClose()
    self.dismiss_callback()
    UIManager:close(self)
    if self.readonly ~= true then
        return true
    end
end

return QRMessage
