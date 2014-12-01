local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local TextWidget = require("ui/widget/textwidget")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Device = require("device")
local UIManager = require("ui/uimanager")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local Input = require("device").input
local Screen = require("device").screen
local Blitbuffer = require("ffi/blitbuffer")

--[[
Widget that displays a tiny notification on top of screen
--]]
local Notification = InputContainer:new{
    face = Font:getFace("infofont", 20),
    text = "Null Message",
    timeout = nil,
    margin = 5,
    padding = 5,
    closed = false,
}

function Notification:init()
    if Device:hasKeys() then
        self.key_events = {
            AnyKeyPressed = { { Input.group.Any }, seqtext = "any key", doc = "close dialog" }
        }
    end
    -- we construct the actual content here because self.text is only available now
    local text_widget = TextWidget:new{
        text = self.text,
        face = self.face
    }
    local widget_size = text_widget:getSize()
    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = Screen:getHeight()/10,
        },
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            radius = 0,
            margin = self.margin,
            padding = self.padding,
            CenterContainer:new{
                dimen = Geom:new{
                    w = widget_size.w,
                    h = widget_size.h
                },
                text_widget,
            }
        }
    }
end

function Notification:close()
    if not self.closed then
        self.closed = true
        UIManager:close(self, "partial", self[1][1].dimen)
    end
end

function Notification:onShow()
    -- triggered by the UIManager after we got successfully shown (not yet painted)
    if self.timeout then
        UIManager:scheduleIn(self.timeout, function() self:close() end)
    end
    self.closed = false
    return true
end

function Notification:onAnyKeyPressed()
    -- triggered by our defined key events
    self:close()
    return true
end

return Notification
