require "ui/widget/base"
require "ui/image"


--[[
ImageWidget shows an image from a file
--]]
ImageWidget = Widget:new{
	invert = nil,
	file = nil,
	_bb = nil
}

function ImageWidget:_render()
	local itype = string.lower(string.match(self.file, ".+%.([^.]+)") or "")
	if itype == "jpeg" or itype == "jpg" then
		self._bb = Image.fromJPEG(self.file)
	elseif itype == "png" then
		self._bb = Image.fromPNG(self.file)
	end
end

function ImageWidget:getSize()
	if not self._bb then
		self:_render()
	end
	return Geom:new{ w = self._bb:getWidth(), h = self._bb:getHeight() }
end

function ImageWidget:paintTo(bb, x, y)
	local size = self:getSize()
	bb:blitFrom(self._bb, x, y, 0, 0, size.w, size.h)
	if self.invert then
		bb:invertRect(x, y, size.w, size.h)
	end
end

function ImageWidget:free()
	if self._bb then
		self._bb:free()
		self._bb = nil
	end
end


