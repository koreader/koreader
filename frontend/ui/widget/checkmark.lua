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

local BD = require("ui/bidi")
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
    _mirroredUI = BD.mirroredUILayout(),
}

function CheckMark:init()
    -- Adjust these checkmarks if mirroring UI (para_direction_rtl should
    -- follow BD.mirroredUILayout(), and not the set or reverted text
    -- direction, for proper rendering on the right).
    local para_direction_rtl = self._mirroredUI
    local checked_widget = TextWidget:new{
        text = " ✓", -- preceded by thin space for better alignment
        face = self.face,
        para_direction_rtl = para_direction_rtl,
    }
    local unchecked_widget = TextWidget:new{
        text = "▢ ",
        face = self.face,
        para_direction_rtl = para_direction_rtl,
    }
    local disabled_checked_widget = TextWidget:new{
        text = " ✓", -- preceded by thin space for better alignment
        face = self.face,
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        para_direction_rtl = para_direction_rtl,
    }
    local disabled_unchecked_widget = TextWidget:new{
        text = "▢ ",
        face = self.face,
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        para_direction_rtl = para_direction_rtl,
    }
    local empty_widget = TextWidget:new{
        text = "",
        face = self.face,
        para_direction_rtl = para_direction_rtl,
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
