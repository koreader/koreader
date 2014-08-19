local Widget = require("ui/widget/widget")
local Image = require("ffi/mupdfimg")
local Geom = require("ui/geometry")

--[[
ImageWidget shows an image from a file
--]]
local ImageWidget = Widget:new{
    file = nil,
    invert = nil,
    dim = nil,
    hide = nil,
    -- if width or height is given, image will rescale to the given size
    width = nil,
    height = nil,
    _bb = nil
}

function ImageWidget:_render()
    local itype = string.lower(string.match(self.file, ".+%.([^.]+)") or "")
    if itype == "png" or itype == "jpg" or itype == "jpeg"
            or itype == "tiff" then
        self._bb = Image:fromFile(self.file, self.width, self.height)
    else
        error("Image file type not supported.")
    end
    local w, h = self._bb:getWidth(), self._bb:getHeight()
    if (self.width and self.width ~= w) or (self.height and self.height ~= h) then
        self._bb = self._bb:scale(self.width or w, self.height or h)
    end
end

function ImageWidget:getSize()
    if not self._bb then
        self:_render()
    end
    return Geom:new{ w = self._bb:getWidth(), h = self._bb:getHeight() }
end

function ImageWidget:rotate(degree)
    if not self._bb then
        self:_render()
    end
    self._bb:rotate(degree)
end

function ImageWidget:paintTo(bb, x, y)
    local size = self:getSize()
    self.dimen = Geom:new{
        x = x, y = y,
        w = size.w,
        h = size.h
    }
    if self.hide then return end
    bb:blitFrom(self._bb, x, y, 0, 0, size.w, size.h)
    if self.invert then
        bb:invertRect(x, y, size.w, size.h)
    end
    if self.dim then
        bb:dimRect(x, y, size.w, size.h)
    end
end

function ImageWidget:free()
    if self._bb then
        self._bb:free()
        self._bb = nil
    end
end

return ImageWidget
