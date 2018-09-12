local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Screen = Device.screen

local ButtonProgressWidget = InputContainer:new{
    width = Screen:scaleBySize(216),
    height = Size.item.height_default,
    font_face = "cfont",
    font_size = 16,
    enabled = true,
    num_buttons = 2,
    position = 1,
}

function ButtonProgressWidget:init()
    self.buttonprogress_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        color = Blitbuffer.COLOR_GREY,
        radius = Size.radius.window,
        bordersize = Size.border.thin,
        padding = Size.padding.small,
        dim = not self.enabled,
        width = self.width,
        height = self.height,
    }

    self.buttonprogress_content = HorizontalGroup:new{}
    self:update()
    self.buttonprogress_frame[1] = self.buttonprogress_content
    self[1] = self.buttonprogress_frame
    self.dimen = Geom:new(self.buttonprogress_frame:getSize())
end

function ButtonProgressWidget:update()
    self.buttonprogress_content:clear()
    local button_margin = Size.margin.tiny
    local button_padding = Size.padding.button
    local button_bordersize = Size.border.button
    local preselect
    local button_width = math.floor(self.width / self.num_buttons) - 2*button_padding - 2*button_margin - 2*button_bordersize
    for i = 1, self.num_buttons do
        if self.position >= i then
            preselect = true
        else
            preselect = false
        end
        local button = Button:new{
            text = "",
            radius = 0,
            margin = button_margin,
            padding = button_padding,
            bordersize = button_bordersize,
            enabled = true,
            width = button_width,
            preselect = preselect,
            text_font_face = self.font_face,
            text_font_size = self.font_size,
            callback = function()
                self.callback(i)
                self.position = i
                self:update()
            end,
            no_focus = true,
            hold_callback = function()
                self.hold_callback(i)
            end,
        }
        table.insert(self.buttonprogress_content, button)
    end

    UIManager:setDirty(self.show_parrent, function()
        return "ui", self.dimen
    end)
end

function ButtonProgressWidget:setPosition(position)
    self.position = position
    self:update()
end

function ButtonProgressWidget:onFocus()
    self.buttonprogress_frame.background = Blitbuffer.COLOR_BLACK
    return true
end

function ButtonProgressWidget:onUnfocus()
    self.buttonprogress_frame.background = Blitbuffer.COLOR_WHITE
    return true
end

function ButtonProgressWidget:onTapSelect(arg, gev)
    if gev == nil then
        self:circlePosition()
    end
end

function ButtonProgressWidget:circlePosition()
    if self.position then
        self.position = self.position+1
        if self.position > self.num_buttons then
            self.position = 1
        end
        self.callback(self.position)
        self:update()
    end
end

return ButtonProgressWidget
