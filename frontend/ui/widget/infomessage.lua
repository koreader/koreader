--[[--
Widget that displays an informational message.

It vanishes on key press or after a given timeout.

Example:
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    local Screen = require("device").screen
    local sample
    sample = InfoMessage:new{
        text = _("Some message"),
        -- Usually the hight of a InfoMessage is self-adaptive. If this field is actively set, a
        -- scrollbar may be shown. This variable is usually helpful to display a large chunk of text
        -- which may exceed the height of the screen.
        height = Screen:scaleBySize(400),
        -- Set to false to hide the icon, and also the span between the icon and text.
        show_icon = false,
        timeout = 5,  -- This widget will vanish in 5 seconds.
    }
    UIManager:show(sample_input)
    sample_input:onShowKeyboard()
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
local IconWidget = require("ui/widget/iconwidget")
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

local InfoMessage = InputContainer:new{
    modal = true,
    face = Font:getFace("infofont"),
    text = "",
    timeout = nil, -- in seconds
    width = nil,  -- The width of the InfoMessage. Keep it nil to use default value.
    height = nil,  -- The height of the InfoMessage. If this field is set, a scrollbar may be shown.
    -- The image shows at the left of the InfoMessage. Image data will be freed
    -- by InfoMessage, caller should not manage its lifecycle
    image = nil,
    image_width = nil,  -- The image width if image is used. Keep it nil to use original width.
    image_height = nil,  -- The image height if image is used. Keep it nil to use original height.
    -- Whether the icon should be shown. If it is false, self.image will be ignored.
    show_icon = true,
    icon = "notice-info",
    alpha = nil, -- if image or icon have an alpha channel (default to true for icons, false for images
    dismiss_callback = nil,
    -- Passed to TextBoxWidget
    alignment = "left",
    -- In case we'd like to use it to display some text we know a few more things about:
    lang = nil,
    para_direction_rtl = nil,
    auto_para_direction = nil,
    -- Don't call setDirty when closing the widget
    no_refresh_on_close = nil,
    -- Only have it painted after this delay (dismissing still works before it's shown)
    show_delay = nil,
    -- Set to true when it might be displayed after some processing, to avoid accidental dismissal
    flush_events_on_show = false,
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

    local image_widget
    if self.show_icon then
        --- @todo remove self.image support, only used in filemanagersearch
        -- this requires self.image's lifecycle to be managed by ImageWidget
        -- instead of caller, which is easy to introduce bugs
        if self.image then
            image_widget = ImageWidget:new{
                image = self.image,
                width = self.image_width,
                height = self.image_height,
                alpha = self.alpha ~= nil and self.alpha or false, -- default to false
            }
        else
            image_widget = IconWidget:new{
                icon = self.icon,
                alpha = self.alpha == nil and true or self.alpha, -- default to true
            }
        end
    else
        image_widget = WidgetContainer:new()
    end

    local text_width
    if self.width == nil then
        text_width = math.floor(Screen:getWidth() * 2/3)
    else
        text_width = self.width - image_widget:getSize().w
        if text_width < 0 then
            text_width = 0
        end
    end

    local text_widget
    if self.height then
        text_widget = ScrollTextWidget:new{
            text = self.text,
            face = self.face,
            width = text_width,
            height = self.height,
            alignment = self.alignment,
            dialog = self,
            lang = self.lang,
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
        }
    else
        text_widget = TextBoxWidget:new{
            text = self.text,
            face = self.face,
            width = text_width,
            alignment = self.alignment,
            lang = self.lang,
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
        }
    end
    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        radius = Size.radius.window,
        HorizontalGroup:new{
            align = "center",
            image_widget,
            HorizontalSpan:new{ width = (self.show_icon and Size.span.horizontal_default or 0) },
            text_widget,
        }
    }
    self.movable = MovableContainer:new{
        frame,
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.movable,
    }
    if not self.height then
        -- Reduce font size until widget fit screen height if needed
        local cur_size = frame:getSize()
        if cur_size and cur_size.h > 0.95 * Screen:getHeight() then
            local orig_font = text_widget.face.orig_font
            local orig_size = text_widget.face.orig_size
            local real_size = text_widget.face.size
            if orig_size > 10 then -- don't go too small
                while true do
                    orig_size = orig_size - 1
                    self.face = Font:getFace(orig_font, orig_size)
                    -- scaleBySize() in Font:getFace() may give the same
                    -- real font size even if we decreased orig_size,
                    -- so check we really got a smaller real font size
                    if self.face.size < real_size then
                        break
                    end
                end
                -- re-init this widget
                self:free()
                self:init()
            end
        end
    end

    if self.show_delay then
        -- Don't have UIManager setDirty us yet
        self.invisible = true
    end
end

function InfoMessage:onCloseWidget()
    if self._delayed_show_action then
        UIManager:unschedule(self._delayed_show_action)
        self._delayed_show_action = nil
    end
    if self.invisible then
        -- Still invisible, no setDirty needed
        return
    end
    if self.no_refresh_on_close then
        return
    end

    UIManager:setDirty(nil, function()
        return "ui", self[1][1].dimen
    end)
end

function InfoMessage:onShow()
    -- triggered by the UIManager after we got successfully show()'n (not yet painted)
    if self.show_delay and self.invisible then
        -- Let us be shown after this delay
        self._delayed_show_action = function()
            self._delayed_show_action = nil
            self.invisible = false
            self:onShow()
        end
        UIManager:scheduleIn(self.show_delay, self._delayed_show_action)
        return true
    end
    -- set our region to be dirty, so UImanager will call our paintTo()
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen
    end)
    if self.flush_events_on_show then
        -- Discard queued and coming up events to avoid accidental dismissal
        UIManager:discardEvents(true)
    end
    -- schedule us to close ourself if timeout provided
    if self.timeout then
        UIManager:scheduleIn(self.timeout, function()
            -- In case we're provided with dismiss_callback, also call it
            -- on timeout
            if self.dismiss_callback then
                self.dismiss_callback()
                self.dismiss_callback = nil
            end
            UIManager:close(self)
        end)
    end
    return true
end

function InfoMessage:getVisibleArea()
    if not self.invisible then
        return self[1][1].dimen
    end
end

function InfoMessage:paintTo(bb, x, y)
    if self.invisible then
        return
    end
    InputContainer.paintTo(self, bb, x, y)
end

function InfoMessage:dismiss()
    if self._delayed_show_action then
        UIManager:unschedule(self._delayed_show_action)
        self._delayed_show_action = nil
    end
    if self.dismiss_callback then
        self.dismiss_callback()
        self.dismiss_callback = nil
    end
    UIManager:close(self)
end

function InfoMessage:onAnyKeyPressed()
    self:dismiss()
    if self.readonly ~= true then
        return true
    end
end

function InfoMessage:onTapClose()
    self:dismiss()
    if self.readonly ~= true then
        return true
    end
end

return InfoMessage
