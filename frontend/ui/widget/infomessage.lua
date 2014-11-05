local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local Device = require("device")
local GestureRange = require("ui/gesturerange")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local ImageWidget = require("ui/widget/imagewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local HorizontalSpan = require("ui/widget/horizontalspan")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Input = require("device").input
local Screen = require("device").screen
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")

--[[
Widget that displays an informational message

it vanishes on key press or after a given timeout
]]
local InfoMessage = InputContainer:new{
    modal = true,
    face = Font:getFace("infofont", 25),
    text = "",
    timeout = nil, -- in seconds
}

function InfoMessage:init()
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
    local image_widget = nil
    if self.image then
        image_widget = ImageWidget:new{
            image = self.image,
            width = self.image_width,
            height = self.image_height,
        }
    else
        image_widget = ImageWidget:new{
            file = "resources/info-i.png",
        }
    end
    -- we construct the actual content here because self.text is only available now
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        FrameContainer:new{
            margin = 2,
            background = Blitbuffer.COLOR_WHITE,
            HorizontalGroup:new{
                align = "center",
                image_widget,
                HorizontalSpan:new{ width = 10 },
                TextBoxWidget:new{
                    text = self.text,
                    face = self.face,
                    width = Screen:getWidth()*2/3,
                }
            }
        }
    }
end

function InfoMessage:onShow()
    -- triggered by the UIManager after we got successfully shown (not yet painted)
    if self.timeout then
        UIManager:scheduleIn(self.timeout, function() UIManager:close(self) end)
    end
    return true
end

function InfoMessage:onAnyKeyPressed()
    -- triggered by our defined key events
    UIManager:close(self)
    return true
end

function InfoMessage:onTapClose()
    UIManager:close(self)
    return true
end

return InfoMessage
