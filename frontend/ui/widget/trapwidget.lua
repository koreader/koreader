--[[--
Invisible full screen widget for catching UI events.
(for use with or by Trapper to interrupt its processing).

Can optionally display a text message at bottom left of screen
(ie: "Loading…")
]]


local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Input = Device.input
local Screen = Device.screen

local TrapWidget = InputContainer:new{
    modal = true,
    dismiss_callback = function() end,
    text = nil, -- will be invisible if no message given
    face = Font:getFace("infofont"),
    -- Whether to resend the event caught and used for dismissal
    resend_event = false,
}

function TrapWidget:init()
    local full_screen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    if Device:hasKeys() then
        self.key_events = {
            AnyKeyPressed = { { Input.group.Any },
                seqtext = "any key", doc = "dismiss" }
        }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapDismiss = {
            GestureRange:new{ ges = "tap", range = full_screen, }
        }
        self.ges_events.HoldDismiss = {
            GestureRange:new{ ges = "hold", range = full_screen, }
        }
        self.ges_events.SwipeDismiss = {
            GestureRange:new{ ges = "swipe", range = full_screen, }
        }
    end
    if self.text then
        local textw = TextWidget:new{
            text = self.text,
            face = self.face,
        }
        -- Don't make our message reach full screen width, so
        -- it looks like popping from bottom left corner
        if textw:getWidth() > Screen:getWidth() * 0.9 then
            -- Text too wide: use TextBoxWidget for multi lines display
            textw = TextBoxWidget:new{
                text = self.text,
                face = self.face,
                width = math.floor(Screen:getWidth() * 0.9)
            }
        end
        local border_size = Size.border.default
        self.frame = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = border_size,
            margin = 0,
            padding = 0,
            padding_left = Size.padding.default,
            padding_right = Size.padding.default,
            textw,
        }
        -- To have our frame message a bit prettier with its left
        -- and bottom borders not displayed, we make use of this
        -- combination of Containers to push them off-screen
        self[1] = CenterContainer:new{
            dimen = full_screen:copy(),
            BottomContainer:new{
                dimen = Geom:new{
                    w = full_screen.w,
                    h = full_screen.h + 2*border_size,
                },
                LeftContainer:new{
                    dimen = Geom:new{
                        w = full_screen.w + 2*border_size,
                        h = self.frame:getSize().h,
                    },
                    self.frame,
                }
            }
        }
    else
        -- So that UIManager knows no refresh is needed and
        -- avoids some unnecessary refreshes
        self.invisible = true
    end
end

function TrapWidget:_dismissAndResent(evtype, ev)
    self.dismiss_callback()
    UIManager:close(self)
    if self.resend_event and evtype and ev then
        -- There may be some timing issues that could cause crashes, as we
        -- use nextTick, if the dismiss_callback uses UIManager:scheduleIn()
        -- or has set up some widget that may catch that event while not being
        -- yet fully initialiazed.
        -- (It happened mostly when I had some bug somewhere, and it was a quite
        -- reliable sign of a bug somewhere, but the stacktrace was unrelated
        -- to the bug location.)
        UIManager:nextTick(function() UIManager:handleInputEvent(Event:new(evtype, ev)) end)
    end
    return true
end

function TrapWidget:onAnyKeyPressed(_, ev)
    return self:_dismissAndResent("KeyPress", ev)
end

function TrapWidget:onTapDismiss(_, ev)
    return self:_dismissAndResent("Gesture", ev)
end

function TrapWidget:onHoldDismiss(_, ev)
    return self:_dismissAndResent("Gesture", ev)
end

function TrapWidget:onSwipeDismiss(_, ev)
    return self:_dismissAndResent("Gesture", ev)
end

function TrapWidget:onShow()
    if self.frame then
        UIManager:setDirty(self, function()
            return "ui", self.frame.dimen
        end)
    end
    return true
end

function TrapWidget:onCloseWidget()
    if self.frame then
        UIManager:setDirty(nil, function()
            return "ui", self.frame.dimen
        end)
    end
end

return TrapWidget
