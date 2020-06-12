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

local ButtonDialogTitle = InputContainer:new{
    title = nil,
    title_align = nil,
    title_face = Font:getFace("x_smalltfont"),
    title_padding = Size.padding.large,
    title_margin = Size.margin.title,
    use_info_style = false, -- set to true to have the same look as ConfirmBox
    info_face = Font:getFace("infofont"),
    info_padding = Size.padding.default,
    info_margin = Size.margin.default,
    buttons = nil,
    tap_close_callback = nil,
    dismissable = true, -- set to false if any button callback is required
}

function ButtonDialogTitle:init()
    if self.dismissable then
        if Device:hasKeys() then
            local close_keys = Device:hasFewKeys() and { "Back", "Left" } or "Back"
            self.key_events = {
                Close = { { close_keys }, doc = "close button dialog" }
            }
        end
        if Device:isTouchDevice() then
            self.ges_events.TapClose = {
                GestureRange:new {
                    ges = "tap",
                    range = Geom:new {
                        x = 0,
                        y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                }
            }
        end
    end
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        MovableContainer:new{
            FrameContainer:new{
                VerticalGroup:new{
                    align = "center",
                    FrameContainer:new{
                        padding = self.use_info_style and self.info_padding or self.title_padding,
                        margin = self.use_info_style and self.info_margin or self.title_margin,
                        bordersize = 0,
                        TextBoxWidget:new{
                            text = self.title,
                            width = math.floor(Screen:getWidth() * 0.8),
                            face = self.use_info_style and self.info_face or self.title_face,
                            alignment = self.title_align or "left",
                        },
                    },
                    VerticalSpan:new{ width = Size.span.vertical_default },
                    ButtonTable:new{
                        width = math.floor(Screen:getWidth() * 0.9),
                        buttons = self.buttons,
                        zero_sep = true,
                        show_parent = self,
                    },
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

function ButtonDialogTitle:onShow()
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen
    end)
end

function ButtonDialogTitle:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self[1][1].dimen
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
    self.dimen = self[1][1].dimen -- FrameContainer
end

return ButtonDialogTitle
