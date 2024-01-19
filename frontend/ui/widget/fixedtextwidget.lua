local TextWidget = require("ui/widget/textwidget")
local Geom = require("ui/geometry")

--[[
FixedTextWidget
--]]
local FixedTextWidget = TextWidget:extend{}

function FixedTextWidget:updateSize()
    TextWidget.updateSize(self)
    -- Only difference from TextWidget:
    -- no vertical padding, baseline is height
    self._height = self.face.size
    self._baseline_h = self.face.size
end

function FixedTextWidget:getSize()
    self:updateSize()
    if self._length == 0 then
        return Geom:new()
    end
    return TextWidget.getSize(self)
end

return FixedTextWidget
