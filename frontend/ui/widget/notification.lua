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

local band = bit.band

-- The following constants are positions in a bitfield
local SOURCE_BOTTOM_MENU_ICON =     0x0001 -- icons in bottom menu
local SOURCE_BOTTOM_MENU_TOGGLE =   0x0002 -- toggles in bottom menu
local SOURCE_BOTTOM_MENU_FINE =     0x0004 -- toggles with fine-tuning ("increase", "+" etc)
local SOURCE_BOTTOM_MENU_MORE =     0x0008 -- three dots in bottom menu
local SOURCE_BOTTOM_MENU_PROGRESS = 0x0010 -- progress indicator on bottom menu
local SOURCE_DISPATCHER =           0x0020 -- dispatcher
local SOURCE_OTHER =                0x0040 -- all other sources (e.g. keyboard)

-- All bottom menu bits
local SOURCE_BOTTOM_MENU = SOURCE_BOTTOM_MENU_ICON + SOURCE_BOTTOM_MENU_TOGGLE + SOURCE_BOTTOM_MENU_FINE +
        SOURCE_BOTTOM_MENU_MORE + SOURCE_BOTTOM_MENU_PROGRESS

-- these values can be changed here
local SOURCE_SOME = SOURCE_BOTTOM_MENU_FINE + SOURCE_DISPATCHER
local SOURCE_DEFAULT = SOURCE_SOME + SOURCE_BOTTOM_MENU_MORE + SOURCE_BOTTOM_MENU_PROGRESS
local SOURCE_ALL = SOURCE_BOTTOM_MENU + SOURCE_DISPATCHER + SOURCE_OTHER

local Notification = InputContainer:new{
    face = Font:getFace("x_smallinfofont"),
    text = "Null Message",
    margin = Size.margin.default,
    padding = Size.padding.default,
    timeout = 2, -- default to 2 seconds
    toast = true, -- closed on any event, and let the event propagate to next top widget

    _nums_shown = {}, -- array of stacked notifications

    SOURCE_BOTTOM_MENU_ICON = SOURCE_BOTTOM_MENU_ICON,
    SOURCE_BOTTOM_MENU_TOGGLE = SOURCE_BOTTOM_MENU_TOGGLE,
    SOURCE_BOTTOM_MENU_FINE = SOURCE_BOTTOM_MENU_FINE,
    SOURCE_BOTTOM_MENU_MORE = SOURCE_BOTTOM_MENU_MORE,
    SOURCE_BOTTOM_MENU_PROGRESS = SOURCE_BOTTOM_MENU_PROGRESS,
    SOURCE_DISPATCHER = SOURCE_DISPATCHER,
    SOURCE_OTHER = SOURCE_OTHER,

    SOURCE_BOTTOM_MENU = SOURCE_BOTTOM_MENU,

    SOURCE_NONE = 0,
    SOURCE_SOME = SOURCE_SOME,
    SOURCE_DEFAULT = SOURCE_DEFAULT,
    SOURCE_ALL = SOURCE_ALL,
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

function Notification:setNotifySource(source)
    self.notify_source = source
end

function Notification:resetNotifySource()
    self.notify_source = Notification.SOURCE_OTHER
end

function Notification:getNotifySource()
    return self.notify_source
end

-- show popups if `self.notify_source` is not masked by the setting `notification_sources_to_show_mask`
function Notification:notify(arg, refresh_after)
    local mask = G_reader_settings:readSetting("notification_sources_to_show_mask") or self.SOURCE_DEFAULT
    if self.notify_source and band(mask, self.notify_source) ~= 0 then
        UIManager:show(Notification:new{
            text = arg,
         })
        if refresh_after then
            UIManager:forceRePaint()
        end
        return true
    end
    return false
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
    local expire_tv = UIManager:getTime() - TimeVal:new{ sec = 30, usec = 0 }
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
