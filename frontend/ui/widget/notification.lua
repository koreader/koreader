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
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local time = require("ui/time")
local _ = require("gettext")
local Screen = Device.screen
local Input = Device.input

local band = bit.band

-- The following constants are positions in a bitfield
local SOURCE_BOTTOM_MENU_ICON     = 0x0001 -- icons in bottom menu
local SOURCE_BOTTOM_MENU_TOGGLE   = 0x0002 -- toggles in bottom menu
local SOURCE_BOTTOM_MENU_FINE     = 0x0004 -- toggles with fine-tuning ("increase", "+" etc)
local SOURCE_BOTTOM_MENU_MORE     = 0x0008 -- three dots in bottom menu
local SOURCE_BOTTOM_MENU_PROGRESS = 0x0010 -- progress indicator on bottom menu
local SOURCE_DISPATCHER           = 0x0020 -- dispatcher
local SOURCE_OTHER                = 0x0040 -- all other sources (e.g. keyboard)
local SOURCE_ALWAYS_SHOW          = 0x8000 -- display this, no matter the display preferences

-- All bottom menu bits
local SOURCE_BOTTOM_MENU = SOURCE_BOTTOM_MENU_ICON +
                           SOURCE_BOTTOM_MENU_TOGGLE +
                           SOURCE_BOTTOM_MENU_FINE +
                           SOURCE_BOTTOM_MENU_MORE +
                           SOURCE_BOTTOM_MENU_PROGRESS

-- these values can be changed here
local SOURCE_SOME = SOURCE_BOTTOM_MENU_FINE
local SOURCE_MORE = SOURCE_SOME +
                    SOURCE_BOTTOM_MENU_MORE +
                    SOURCE_BOTTOM_MENU_PROGRESS
local SOURCE_DEFAULT = SOURCE_MORE +
                       SOURCE_DISPATCHER
local SOURCE_ALL = SOURCE_BOTTOM_MENU +
                   SOURCE_DISPATCHER +
                   SOURCE_OTHER

-- Maximum number of saved message text
local MAX_NB_PAST_MESSAGES = 20

local Notification = InputContainer:extend{
    face = Font:getFace("x_smallinfofont"),
    text = _("N/A"),
    margin = Size.margin.default,
    padding = Size.padding.default,
    timeout = 2, -- default to 2 seconds
    _timeout_func = nil,
    toast = true, -- closed on any event, and let the event propagate to next top widget

    _shown_list = {}, -- actual static class member, array of stacked notifications (value is show (well, init) time or false).
    _shown_idx = nil, -- index of this instance in the class's _shown_list array (assumes each Notification object is only shown (well, init) once).

    SOURCE_BOTTOM_MENU_ICON = SOURCE_BOTTOM_MENU_ICON,
    SOURCE_BOTTOM_MENU_TOGGLE = SOURCE_BOTTOM_MENU_TOGGLE,
    SOURCE_BOTTOM_MENU_FINE = SOURCE_BOTTOM_MENU_FINE,
    SOURCE_BOTTOM_MENU_MORE = SOURCE_BOTTOM_MENU_MORE,
    SOURCE_BOTTOM_MENU_PROGRESS = SOURCE_BOTTOM_MENU_PROGRESS,
    SOURCE_DISPATCHER = SOURCE_DISPATCHER,
    SOURCE_OTHER = SOURCE_OTHER,
    SOURCE_ALWAYS_SHOW = SOURCE_ALWAYS_SHOW,

    SOURCE_BOTTOM_MENU = SOURCE_BOTTOM_MENU,

    SOURCE_NONE = 0,
    SOURCE_SOME = SOURCE_SOME,
    SOURCE_MORE = SOURCE_MORE,
    SOURCE_DEFAULT = SOURCE_DEFAULT,
    SOURCE_ALL = SOURCE_ALL,

    _past_messages = {}, -- a static class member to store the N last messages text
}

function Notification:init()
    if not self.toast then
        -- If not toast, closing is handled in here
        if Device:hasKeys() then
            self.key_events.AnyKeyPressed = { { Input.group.Any } }
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
        max_width = Screen:getWidth() - 2 * (self.margin + self.padding)
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
    table.insert(Notification._shown_list, UIManager:getTime())
    self._shown_idx = #Notification._shown_list

    self[1] = VerticalGroup:new{
        align = "center",
        -- We use a span to properly position this notification:
        RectSpan:new{
            -- have this VerticalGroup full width, to ensure centering
            width = Screen:getWidth(),
            -- push this frame at its y=self._shown_idx position
            height = notif_height * (self._shown_idx - 1) + self.margin,
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
    self.notify_source = SOURCE_OTHER
end

function Notification:getNotifySource()
    return self.notify_source
end

-- Display a notification popup if `source` or `self.notify_source` is not masked by the `notification_sources_to_show_mask` setting
function Notification:notify(arg, source, refresh_after)
    source = source or self.notify_source
    local mask = G_reader_settings:readSetting("notification_sources_to_show_mask") or SOURCE_DEFAULT
    if source and (source == SOURCE_ALWAYS_SHOW or band(mask, source) ~= 0) then
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

function Notification:getPastMessages()
    return self._past_messages
end

function Notification:_cleanShownStack()
    -- Clean stack of shown notifications
    if self._shown_idx then
        -- If this field exists, this is the first time this instance was closed since its init.
        -- This notification is no longer displayed
        Notification._shown_list[self._shown_idx] = false
    end
    -- We remove from the stack's tail all slots no longer displayed.
    -- Even if slots at top are available, we'll keep adding new
    -- notifications only at the tail/bottom (easier for the eyes
    -- to follow what is happening).
    -- As a sanity check, we also forget those shown for
    -- more than 30s in case no close event was received.
    local expire_time = UIManager:getTime() - time.s(30)
    for i = #Notification._shown_list, 1, -1 do
        if Notification._shown_list[i] and Notification._shown_list[i] > expire_time then
            break -- still shown (or not yet expired)
        end
        table.remove(Notification._shown_list, i)
    end
end

function Notification:onCloseWidget()
    self:_cleanShownStack()
    self._shown_idx = nil -- Don't do something stupid if this same instance gets closed multiple times
    UIManager:setDirty(nil, function()
        return "ui", self.frame.dimen
    end)
    -- If we were closed early, drop the scheduled timeout
    if self._timeout_func then
        UIManager:unschedule(self._timeout_func)
        self._timeout_func = nil
    end
end

function Notification:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.frame.dimen
    end)
    if self.timeout then
        self._timeout_func = function()
            self._timeout_func = nil
            UIManager:close(self)
        end
        UIManager:scheduleIn(self.timeout, self._timeout_func)
    end

    if #self._past_messages >= MAX_NB_PAST_MESSAGES then
        table.remove(self._past_messages)
    end
    table.insert(self._past_messages, 1, os.date("%X: ") .. self.text)

    return true
end

function Notification:onTapClose()
    if self.toast then return end -- should not happen
    UIManager:close(self)
    return true
end
Notification.onAnyKeyPressed = Notification.onTapClose

-- Toasts should go bye-bye on user input, without stopping the event's propagation.
function Notification:onKeyPress(key)
    if self.toast then
        UIManager:close(self)
        return false
    end
    return InputContainer.onKeyPress(self, key)
end
function Notification:onKeyRepeat(key)
    if self.toast then
        UIManager:close(self)
        return false
    end
    return InputContainer.onKeyRepeat(self, key)
end
function Notification:onGesture(ev)
    if self.toast then
        UIManager:close(self)
        return false
    end
    return InputContainer.onGesture(self, ev)
end

-- Since toasts do *not* prevent event propagation, if we let this go through to InputContainer, shit happens...
function Notification:onIgnoreTouchInput(toggle)
    return true
end
-- Do the same for other Events caught by our base class
Notification.onResume = Notification.onIgnoreTouchInput
Notification.onPhysicalKeyboardDisconnected = Notification.onIgnoreTouchInput
Notification.onInput = Notification.onIgnoreTouchInput

return Notification
