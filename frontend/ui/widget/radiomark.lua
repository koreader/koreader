local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local RadioMark = WidgetContainer:extend{
    checkable = true, -- empty space when false
    checked = false,
    enabled = true,
    face = Font:getFace("smallinfofont"),
    baseline = 0,
    _mirroredUI = BD.mirroredUILayout(),
    -- round radio mark looks a little bit higher than the button/menu text
    -- default vertical down shift ratio (to the text height) looks good in touchmenu
    v_shift_ratio = 0.03,
}

function RadioMark:init()
    local widget = TextWidget:new{
        text = self.checkable and (self.checked and "◉ " or "◯ ") or "",
        face = self.face,
        fgcolor = self.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
        para_direction_rtl = self._mirroredUI,
    }
    self.baseline = widget:getBaseline()
    widget.forced_baseline = self.baseline + math.floor(widget:getSize().h * self.v_shift_ratio)
    self[1] = widget
    self.dimen = widget:getSize()
end

return RadioMark
