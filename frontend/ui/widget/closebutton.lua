--[[--
Button widget that shows an "×" and handles closing window when tapped

Example:

    local parent_widget = HorizontalGroup:new{}
    table.insert(parent_widget, CloseButton:new{
        window = parent_widget,
    })
    UIManager:show(parent_widget)

]]

local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local TextWidget = require("ui/widget/textwidget")
local GestureRange = require("ui/gesturerange")
local Font = require("ui/font")

local CloseButton = InputContainer:new{
    overlap_align = "right",
    window = nil,
}

function CloseButton:init()
    local text_widget = TextWidget:new{
        text = "×",
        face = Font:getFace("cfont", 32),
    }
    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        text_widget
    }

    self.dimen = text_widget:getSize()

    self.ges_events.Close = {
        GestureRange:new{
            ges = "tap",
            range = self.dimen,
        },
        doc = "Tap on close button",
    }
end

function CloseButton:onClose()
    self.window:onClose()
    return true
end

return CloseButton
