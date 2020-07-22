--[[--
Widget that displays zoomed pic.

It vanishes on key press or after a given timeout.

Example:
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    local Screen = require("device").screen
    local magnifier
    magnifier = Magnifier:new{
        image = Image,
        height = Screen:scaleBySize(400),
        width = Screen:scaleBySize(400),
        timeout = 5,  -- This widget will vanish in 5 seconds.
    }
    UIManager:show(magnifier)
    magnifier:onShowKeyboard()
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen

local Magnifier = InputContainer:new{
    image = nil,
    timeout = nil, -- in seconds
    width = nil,  -- The width of the Magnifier. Keep it nil to use default value.
    height = nil,  -- The height of the Magnifier. 
    alpha = false, -- does that icon have an alpha channel?
    dismiss_callback = function() end,
}

function Magnifier:init()
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

    local image_widget
    image_widget = ImageWidget:new{
        image = self.image,
        width = self.width-10,
        height = self.height-10,
        alpha = self.alpha,
    }

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        HorizontalGroup:new{
            align = "center",
            image_widget
        }
    }
    self.movable = MovableContainer:new{
        frame,
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.movable,
    }
  
end

function Magnifier:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self[1][1].dimen
    end)
    return true
end

function Magnifier:onShow()
    -- triggered by the UIManager after we got successfully shown (not yet painted)
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen
    end)
    if self.timeout then
        UIManager:scheduleIn(self.timeout, function() UIManager:close(self) end)
    end
    return true
end

function Magnifier:onAnyKeyPressed()
    -- triggered by our defined key events
    self.dismiss_callback()
    UIManager:close(self)
    if self.readonly ~= true then
        return true
    end
end

function Magnifier:onTapClose()
    self.dismiss_callback()
    UIManager:close(self)
    if self.readonly ~= true then
        return true
    end
end

return Magnifier
