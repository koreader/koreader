--[[--
Widget that displays an informational message.

It vanishes on key press or after a given timeout.

Example:
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    local sample
    sample = InfoMessage:new{
        text = _("Some message"),
        -- Usually the hight of a InfoMessage is self-adaptive. If this field is actively set, a
        -- scrollbar may be shown. This variable is usually helpful to display a large chunk of text
        -- which may exceed the height of the screen.
        height = 400,
        -- Set to false to hide the icon, and also the span between the icon and text.
        show_icon = false,
        timeout = 5,  -- This widget will vanish in 5 seconds.
    }
    sample_input:onShowKeyboard()
    UIManager:show(sample_input)
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
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
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
        -- TODO: remove self.image support, only used in filemanagersearch
        -- this requires self.image's lifecycle to be managed by ImageWidget
        -- instead of caller, which is easy to introduce bugs
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
    else
        image_widget = WidgetContainer:new()
    end

    local text_width
    if self.width == nil then
        text_width = Screen:getWidth() * 2 / 3
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
            dialog = self,
        }
    else
        text_widget = TextBoxWidget:new{
            text = self.text,
            face = self.face,
            width = text_width,
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
                HorizontalSpan:new{ width = (self.show_icon and 10 or 0) },
                text_widget,
            }
        }
    }
end

function InfoMessage:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self[1][1].dimen
    end)
    return true
end

function InfoMessage:onShow()
    -- triggered by the UIManager after we got successfully shown (not yet painted)
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen
    end)
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
