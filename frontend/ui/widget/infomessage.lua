local InputContainer = require("ui/widget/container/inputcontainer")
local Font = require("ui/font")
local Device = require("ui/device")
local GestureRange = require("ui/gesturerange")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local ImageWidget = require("ui/widget/imagewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local HorizontalSpan = require("ui/widget/horizontalspan")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local CenterContainer = require("ui/widget/container/centercontainer")
local Input = require("ui/input")
local Screen = require("ui/screen")
local _ = require("gettext")

--[[
Widget that displays an informational message

it vanishes on key press or after a given timeout
]]
local InfoMessage = InputContainer:new{
    face = Font:getFace("infofont", 25),
    text = "",
    timeout = nil, -- in seconds
}

function InfoMessage:init()
    if Device:hasKeyboard() then
        self.key_events = {
            AnyKeyPressed = { { Input.group.Any },
                seqtext = "any key", doc = _("close dialog") }
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
    -- we construct the actual content here because self.text is only available now
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        FrameContainer:new{
            margin = 2,
            background = 0,
            HorizontalGroup:new{
                align = "center",
                ImageWidget:new{
                    file = "resources/info-i.png"
                },
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
