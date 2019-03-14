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

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")

local CheckMark = InputContainer:new{
    checkable = true,
    checked = false,
    enabled = true,
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
    local disabled_checked_widget = TextWidget:new{
        text = " ✓", -- preceded by thin space for better alignment
        face = self.face,
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    }
    local disabled_unchecked_widget = TextWidget:new{
        text = "▢ ",
        face = self.face,
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    }
    local empty_widget = TextWidget:new{
        text = "",
        face = self.face,
    }
    local widget
    if self.checkable then
        if self.enabled then
            widget = OverlapGroup:new{
                (self.checked and checked_widget or empty_widget),
                unchecked_widget
            }
        else
            widget = OverlapGroup:new{
                (self.checked and disabled_checked_widget or empty_widget),
                disabled_unchecked_widget
            }
        end
    else
        widget = empty_widget
    end
    self[1] = widget
    self.dimen = unchecked_widget:getSize()
end

return CheckMark
