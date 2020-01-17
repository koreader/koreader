--[[--
Button widget that shows an "×" and handles closing window when tapped

Example:

    local CloseButton = require("ui/widget/closebutton")
    local parent_widget = OverlapGroup:new{}
    table.insert(parent_widget, CloseButton:new{
        window = parent_widget,
    })
    UIManager:show(parent_widget)

]]

local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local Screen = require("device").screen

local CloseButton = InputContainer:new{
    overlap_align = "right",
    window = nil,
    padding_left = Screen:scaleBySize(14), -- for larger touch area
    padding_right = 0,
    padding_top = 0,
    padding_bottom = 0,
}

function CloseButton:init()
    local text_widget = TextWidget:new{
        text = "×",
        face = Font:getFace("cfont", 30),
    }

    -- The text box height is greater than its width, and we want this × to be
    -- diagonally aligned with the top right corner (assuming padding_right=0,
    -- or padding_right = padding_top so the diagonal aligment is preserved).
    local text_size = text_widget:getSize()
    local text_width_pad = (text_size.h - text_size.w) / 2

    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        padding_top = self.padding_top,
        padding_bottom = self.padding_bottom,
        padding_left = self.padding_left,
        padding_right = self.padding_right + text_width_pad,
        text_widget,
    }

    self.ges_events.Close = {
        GestureRange:new{
            ges = "tap",
            -- x and y coordinates for the widget is only known after the it is
            -- drawn. so use callback to get range at runtime.
            range = function() return self.dimen end,
        },
        doc = "Tap on close button",
    }

    self.ges_events.HoldClose = {
        GestureRange:new{
            ges = "hold_release",
            range = function() return self.dimen end,
        },
        doc = "Hold on close button",
    }
end

function CloseButton:onClose()
    if self.window.onClose then
        self.window:onClose()
    end
    return true
end

function CloseButton:onHoldClose()
    if self.window.onHoldClose then
        self.window:onHoldClose()
    end
    return true
end

return CloseButton
