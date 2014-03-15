local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Device = require("ui/device")
local UIManager = require("ui/uimanager")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local Input = require("ui/input")
local Screen = require("ui/screen")

--[[
Widget that displays a tiny notification on top of screen
--]]
local Notification = InputContainer:new{
    face = Font:getFace("infofont", 20),
    text = "Null Message",
    timeout = nil,
}

function Notification:init()
    if Device:hasKeyboard() then
        self.key_events = {
            AnyKeyPressed = { { Input.group.Any }, seqtext = "any key", doc = "close dialog" }
        }
    end
    -- we construct the actual content here because self.text is only available now
    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = Screen:getHeight()/10,
        },
        ignore = "height",
        FrameContainer:new{
            background = 0,
            radius = 0,
            HorizontalGroup:new{
                align = "center",
                TextBoxWidget:new{
                    text = self.text,
                    face = self.face,
                }
            }
        }
    }
end

function Notification:onShow()
    -- triggered by the UIManager after we got successfully shown (not yet painted)
    if self.timeout then
        UIManager:scheduleIn(self.timeout, function() UIManager:close(self) end)
    end
    return true
end

function Notification:onAnyKeyPressed()
    -- triggered by our defined key events
    UIManager:close(self)
    return true
end

return Notification
