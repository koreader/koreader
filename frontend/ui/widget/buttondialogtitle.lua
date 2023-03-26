local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local UIManager = require("ui/uimanager")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen

local ButtonDialogTitle = InputContainer:extend{
    title = nil,
    title_align = nil,
    title_face = Font:getFace("x_smalltfont"),
    title_padding = Size.padding.large,
    title_margin = Size.margin.title,
    width = nil,
    width_factor = nil, -- number between 0 and 1, factor to the smallest of screen width and height
    use_info_style = true, -- set to false to have bold font style of the title
    info_face = Font:getFace("infofont"),
    info_padding = Size.padding.default,
    info_margin = Size.margin.default,
    buttons = nil,
    tap_close_callback = nil,
    dismissable = true, -- set to false if any button callback is required
}

function ButtonDialogTitle:init()
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    if not self.width then
        if not self.width_factor then
            self.width_factor = 0.9 -- default if no width specified
        end
        self.width = math.floor(math.min(self.screen_width, self.screen_height) * self.width_factor)
    end
    if self.dismissable then
        if Device:hasKeys() then
            local close_keys = Device:hasFewKeys() and { "Back", "Left" } or Device.input.group.Back
            self.key_events.Close = { { close_keys } }
        end
        if Device:isTouchDevice() then
            self.ges_events.TapClose = {
                GestureRange:new {
                    ges = "tap",
                    range = Geom:new {
                        x = 0,
                        y = 0,
                        w = self.screen_width,
                        h = self.screen_height,
                    }
                }
            }
        end
    end

    self.button_table = ButtonTable:new{
        width = self.width - 2*Size.border.window - 2*Size.padding.button,
        buttons = self.buttons,
        zero_sep = true,
        show_parent = self,
    }

    local title_padding = self.use_info_style and self.info_padding or self.title_padding
    local title_margin = self.use_info_style and self.info_margin or self.title_margin
    local title_width = self.width - 2 * (Size.border.window + Size.padding.button + title_padding + title_margin)
    local title_widget = FrameContainer:new{
        padding = title_padding,
        margin = title_margin,
        bordersize = 0,
        TextBoxWidget:new{
            text = self.title,
            width = title_width,
            face = self.use_info_style and self.info_face or self.title_face,
            alignment = self.title_align or "left",
        },
    }

    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        ignore_if_over = "height",
        MovableContainer:new{
            anchor = self.anchor,
            FrameContainer:new{
                VerticalGroup:new{
                    align = "center",
                    title_widget,
                    VerticalSpan:new{ width = Size.span.vertical_default },
                    self.button_table,
                },
                background = Blitbuffer.COLOR_WHITE,
                bordersize = Size.border.window,
                radius = Size.radius.window,
                padding = Size.padding.button,
                padding_bottom = 0, -- no padding below buttontable
            }
        }
    }
end

function ButtonDialogTitle:setTitle(title)
    self.title = title
    self:free()
    self:init()
    UIManager:setDirty("all", "ui")
end

function ButtonDialogTitle:onShow()
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen -- i.e., MovableContainer
    end)
end

function ButtonDialogTitle:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self[1][1].dimen
    end)
end

function ButtonDialogTitle:onTapClose()
    UIManager:close(self)
    if self.tap_close_callback then
        self.tap_close_callback()
    end
    return true
end

function ButtonDialogTitle:onClose()
    self:onTapClose()
    return true
end

function ButtonDialogTitle:paintTo(...)
    InputContainer.paintTo(self, ...)
    self.dimen = self[1][1].dimen
end

return ButtonDialogTitle
