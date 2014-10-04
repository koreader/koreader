local Widget = require("ui/widget/widget")
local Screen = require("ui/screen")
local RenderText = require("ui/rendertext")
local Geom = require("ui/geometry")

--[[
A TextWidget puts a string on a single line
--]]
local TextWidget = Widget:new{
    text = nil,
    face = nil,
    bold = nil,
    fgcolor = 1.0, -- [0.0, 1.0]
    _bb = nil,
    _length = 0,
    _height = 0,
    _maxlength = 1200,
}

--function TextWidget:_render()
    --local h = self.face.size * 1.3
    --self._bb = Blitbuffer.new(self._maxlength, h)
    --self._length = RenderText:renderUtf8Text(self._bb, 0, h*0.8, self.face, self.text, true, self.bold)
--end

function TextWidget:getSize()
    --if not self._bb then
        --self:_render()
    --end
    --return { w = self._length, h = self._bb:getHeight() }
    local tsize = RenderText:sizeUtf8Text(0, Screen:getWidth(), self.face, self.text, true, self.bold)
    if not tsize then
        return Geom:new{}
    end
    self._length = tsize.x
    self._height = self.face.size * 1.5
    return Geom:new{
        w = self._length,
        h = self._height,
    }
end

function TextWidget:paintTo(bb, x, y)
    --if not self._bb then
        --self:_render()
    --end
    --bb:blitFrom(self._bb, x, y, 0, 0, self._length, self._bb:getHeight())
    --@TODO Don't use kerning for monospaced fonts.    (houqp)
    RenderText:renderUtf8Text(bb, x, y+self._height*0.7, self.face, self.text, true, self.bold,
                self.fgcolor, self.width)
end

function TextWidget:free()
    if self._bb then
        self._bb:free()
        self._bb = nil
    end
end

return TextWidget
