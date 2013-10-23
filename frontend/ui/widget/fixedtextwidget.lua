local TextWidget = require("ui/widget/textwidget")
local RenderText = require("ui/rendertext")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")

--[[
FixedTextWidget
--]]
local FixedTextWidget = TextWidget:new{}

function FixedTextWidget:getSize()
	local tsize = RenderText:sizeUtf8Text(0, Screen:getWidth(), self.face, self.text, true)
	if not tsize then
		return Geom:new{}
	end
	self._length = tsize.x
	self._height = self.face.size
	return Geom:new{
		w = self._length,
		h = self._height,
	}
end

function FixedTextWidget:paintTo(bb, x, y)
	RenderText:renderUtf8Text(bb, x, y+self._height, self.face, self.text,
					true, self.bgcolor, self.fgcolor)
end

return FixedTextWidget
