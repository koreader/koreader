--[[--
Widget that shows a checkmark (`✓`), an empty box (`□`)
or nothing of the same size.

Example:

    local CheckMark = require("ui/widget/CheckMark")
    local parent_widget = FrameContainer:new{}
    table.insert(parent_widget, CheckMark:new{
        checkable = false, -- shows nothing when false, defaults to true
        checked = function() end, -- whether the box has a checkmark in it
    })
    UIManager:show(parent_widget)

]]

local Font = require("ui/font")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")

local CheckMark = InputContainer:new{
    checkable = true,
    checked = false,
    face = Font:getFace("smallinfofont"),
    width = 0,
    height = 0,
}

function CheckMark:init()
    local checked_widget = TextWidget:new{
        text = " ✓", -- preceded by thin space for better alignment
        face = self.face,
    }
    local unchecked_widget = TextWidget:new{
        text = "▢ ",
        face = self.face,
    }
    local empty_widget = TextWidget:new{
        text = "",
        face = self.face,
    }
    self[1] = self.checkable and OverlapGroup:new{
        (self.checked and checked_widget or empty_widget),
        unchecked_widget
    }
    or empty_widget

    self.dimen = unchecked_widget:getSize()
end

return CheckMark
