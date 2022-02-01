local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")

local RadioMark = InputContainer:new{
    checkable = true, -- empty space when false
    checked = false,
    enabled = true,
    face = Font:getFace("smallinfofont"),
    baseline = 0,
    _mirroredUI = BD.mirroredUILayout(),
}

function RadioMark:init()
    local widget = TextWidget:new{
        text = self.checkable and (self.checked and "◉ " or "◯ ") or "",
        face = self.face,
        fgcolor = self.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
        para_direction_rtl = self._mirroredUI,
    }
    self.baseline = widget:getBaseline()
    self[1] = widget
    self.dimen = widget:getSize()
end

return RadioMark
