--[[--
Widget that displays a tiny notification at the top of the screen.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RectSpan = require("ui/widget/rectspan")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TimeVal = require("ui/timeval")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Input = Device.input
local Screen = Device.screen

local Notification = InputContainer:new{
    face = Font:getFace("x_smallinfofont"),
    text = "Null Message",
    margin = Size.margin.default,
    padding = Size.padding.default,
    timeout = 2, -- default to 2 seconds
    toast = true, -- closed on any event, and let the event propagate to next top widget

    _nums_shown = {}, -- array of stacked notifications
}

function Notification:init()
    if not self.toast then
        -- If not toast, closing is handled in here
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
    end

    local text_widget = TextWidget:new{
        text = self.text,
        face = self.face,
    }
    local widget_size = text_widget:getSize()
    self.frame = FrameContainer:new{
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
    local notif_height = self.frame:getSize().h

    self:_cleanShownStack()
    table.insert(Notification._nums_shown, UIManager:getTime())
    self.num = #Notification._nums_shown

    self[1] = VerticalGroup:new{
        align = "center",
        -- We use a span to properly position this notification:
        RectSpan:new{
            -- have this VerticalGroup full width, to ensure centering
            width = Screen:getWidth(),
            -- push this frame at its y=self.num position
            height = notif_height * (self.num - 1) + self.margin,
                -- (let's add a leading self.margin to get the same distance
                -- from top of screen to first notification top border as
                -- between borders of next notifications)
        },
        self.frame,
    }
end

function Notification:_cleanShownStack(num)
    -- Clean stack of shown notifications
    if num then
        -- This notification is no longer displayed
        Notification._nums_shown[num] = false
    end
    -- We remove from the stack tail all slots no longer displayed.
    -- Even if slots at top are available, we'll keep adding new
    -- notifications only at the tail/bottom (easier for the eyes
    -- to follow what is happening).
    -- As a sanity check, we also forget those shown for
    -- more than 30s in case no close event was received.
    local expire_tv = UIManager:getTime() - TimeVal:new{ sec = 30 }
    for i=#Notification._nums_shown, 1, -1 do
        if Notification._nums_shown[i] and Notification._nums_shown[i] > expire_tv then
            break -- still shown (or not yet expired)
        end
        table.remove(Notification._nums_shown, i)
    end
end

function Notification:onCloseWidget()
    self:_cleanShownStack(self.num)
    self.num = nil -- avoid mess in case onCloseWidget is called multiple times
    UIManager:setDirty(nil, function()
        return "ui", self.frame.dimen
    end)
    return true
end

function Notification:onShow()
    -- triggered by the UIManager after we got successfully shown (not yet painted)
    UIManager:setDirty(self, function()
        return "ui", self.frame.dimen
    end)
    if self.timeout then
        UIManager:scheduleIn(self.timeout, function() UIManager:close(self) end)
    end
    return true
end

function Notification:onAnyKeyPressed()
    if self.toast then return end -- should not happen
    UIManager:close(self)
    return true
end

function Notification:onTapClose()
    if self.toast then return end -- should not happen
    UIManager:close(self)
    return true
end

return Notification
