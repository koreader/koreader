--[[--
Widget that displays an informational message.

It vanishes on key press or after a given timeout.

Example:
    local InfoMessage = require("ui/widget/infomessage")
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    local Screen = require("device").screen
    local sample
    sample = InfoMessage:new{
        text = _("Some message"),
        -- Usually the height of a InfoMessage is self-adaptive. If this field is actively set, a
        -- scrollbar may be shown. This variable is usually helpful to display a large chunk of text
        -- which may exceed the height of the screen.
        height = Screen:scaleBySize(400),
        -- Set to false to hide the icon, and also the span between the icon and text.
        show_icon = false,
        timeout = 5,  -- This widget will vanish in 5 seconds.
    }
    UIManager:show(sample)
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

local InfoMessage = InputContainer:extend{
    modal = true,
    face = nil,
    monospace_font = false,
    text = "",
    timeout = nil, -- in seconds
    _timeout_func = nil,
    width = nil,  -- The width of the InfoMessage. Keep it nil to use default value.
    height = nil,  -- The height of the InfoMessage. If this field is set, a scrollbar may be shown.
    force_one_line = false,  -- Attempt to show text in one single line. This setting and height are not to be used conjointly.
    -- The image shows at the left of the InfoMessage. Image data will be freed
    -- by InfoMessage, caller should not manage its lifecycle
    image = nil,
    image_width = nil,  -- The image width if image is used. Keep it nil to use original width.
    image_height = nil,  -- The image height if image is used. Keep it nil to use original height.
    -- Whether the icon should be shown. If it is false, self.image will be ignored.
    show_icon = true,
    icon = "notice-info",
    alpha = nil, -- if image or icon have an alpha channel (default to true for icons, false for images
    dismissable = true,
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
    if not self.face then
        self.face = Font:getFace(self.monospace_font and "infont" or "infofont")
    end

    if self.dismissable then
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
        unmovable = self.unmovable,
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.movable,
    }

    if not self.height then
        local max_height
        if self.force_one_line and not self.text:find("\n") then
            local icon_height = self.show_icon and image_widget:getSize().h or 0
            -- Calculate the size of the frame container when it's only displaying one line.
            max_height = math.max(text_widget:getLineHeight(), icon_height) + 2*frame.bordersize + 2*frame.padding
        else
            max_height = Screen:getHeight() * 0.95
        end

        -- Reduce font size if the text is too long
        local cur_size = frame:getSize()
        if self.force_one_line and not (self._initial_orig_font and self._initial_orig_size) then
            self._initial_orig_font = text_widget.face.orig_font
            self._initial_orig_size = text_widget.face.orig_size
        end
        if cur_size and cur_size.h > max_height then
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
                if self.force_one_line and orig_size < 16 then
                    -- Do not reduce the font size any longer, at around this point, our font is too small for the max_height check to be useful
                    -- anymore (when icon_height), at those sizes (or lower) two lines fit inside the max_height so, simply disable it.
                    self.face = Font:getFace(self._initial_orig_font, self._initial_orig_size)
                    self.force_one_line = false
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
    -- If we were closed early, drop the scheduled timeout
    if self._timeout_func then
        UIManager:unschedule(self._timeout_func)
        self._timeout_func = nil
    end

    if self._delayed_show_action then
        UIManager:unschedule(self._delayed_show_action)
        self._delayed_show_action = nil
    end
    if self.dismiss_callback then
        self.dismiss_callback()
        -- NOTE: Dirty hack for Trapper, which needs to pull a Lazarus on dead widgets while preserving the callback's integrity ;).
        if not self.is_infomessage then
            self.dismiss_callback = nil
        end
    end

    if self.invisible then
        -- Still invisible, no setDirty needed
        return
    end
    if self.no_refresh_on_close then
        return
    end

    UIManager:setDirty(nil, function()
        return "ui", self.movable.dimen
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
        return "ui", self.movable.dimen
    end)
    if self.flush_events_on_show then
        -- Discard queued and upcoming input events to avoid accidental dismissal
        Input:inhibitInputUntil(true)
    end
    -- schedule a close on timeout, if any
    if self.timeout then
        self._timeout_func = function()
            self._timeout_func = nil
            UIManager:close(self)
        end
        UIManager:scheduleIn(self.timeout, self._timeout_func)
    end
    return true
end

function InfoMessage:getVisibleArea()
    if not self.invisible then
        return self.movable.dimen
    end
end

function InfoMessage:paintTo(bb, x, y)
    if self.invisible then
        return
    end
    InputContainer.paintTo(self, bb, x, y)
end

function InfoMessage:onTapClose()
    UIManager:close(self)
    if self.readonly ~= true then
        return true
    end
end
InfoMessage.onAnyKeyPressed = InfoMessage.onTapClose

return InfoMessage
