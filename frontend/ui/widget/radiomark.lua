local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local RadioMark = InputContainer:new{
    checkable = true, -- empty space when false
    checked = false,
    enabled = true,
    face = Font:getFace("smallinfofont"),
    baseline = 0,
    _mirroredUI = BD.mirroredUILayout(),
    -- round radio mark looks a little bit upper than the button/menu text
    -- default vertical down shift ratio (to the text height) looks good in touchmenu
    v_shift_ratio = 0.05,
}

function RadioMark:init()
    local text_widget = TextWidget:new{
        text = self.checkable and (self.checked and "◉ " or "◯ ") or "",
        face = self.face,
        fgcolor = self.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
        para_direction_rtl = self._mirroredUI,
    }
    self.baseline = text_widget:getBaseline()
    local pad = math.floor(text_widget:getSize().h * self.v_shift_ratio)
    local widget = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = pad },
        text_widget,
    }
    self[1] = widget
    self.dimen = widget:getSize()
end

return RadioMark
