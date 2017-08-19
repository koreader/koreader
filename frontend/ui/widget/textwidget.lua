--[[--
A TextWidget puts a string on a single line.

Example:

    UIManager:show(TextWidget:new{
        text = "Make it so.",
        face = Font:getFace("cfont"),
        bold = true,
        fgcolor = Blitbuffer.COLOR_GREY,
    })

--]]

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local RenderText = require("ui/rendertext")
local Widget = require("ui/widget/widget")
local Screen = require("device").screen

local TextWidget = Widget:new{
    text = nil,
    face = nil,
    bold = nil,
    fgcolor = Blitbuffer.COLOR_BLACK,
    max_width = nil,
    _bb = nil,
    _length = 0,
    _height = 0,
    _maxlength = 1200,
}

--function TextWidget:_render()
    --local h = self.face.size * 1.3
    --self._bb = Blitbuffer.new(self._maxlength, h)
    --self._bb:fill(Blitbuffer.COLOR_WHITE)
    --self._length = RenderText:renderUtf8Text(self._bb, 0, h*0.8, self.face, self.text, true, self.bold)
--end

function TextWidget:updateSize()
    local tsize = RenderText:sizeUtf8Text(0, self.max_width and self.max_width or Screen:getWidth(), self.face, self.text, true, self.bold)
    if not tsize then
        self._length = 0
    else
        self._length = math.ceil(tsize.x)
    end
    self._height = math.ceil(self.face.size * 1.5)
end

function TextWidget:getSize()
    --if not self._bb then
        --self:_render()
    --end
    --return { w = self._length, h = self._bb:getHeight() }
    self:updateSize()
    return Geom:new{
        w = self._length,
        h = self._height,
    }
end

function TextWidget:setText(text)
    self.text = text
    self:updateSize()
end

function TextWidget:paintTo(bb, x, y)
    --if not self._bb then
        --self:_render()
    --end
    --bb:blitFrom(self._bb, x, y, 0, 0, self._length, self._bb:getHeight())
    --@TODO Don't use kerning for monospaced fonts.    (houqp)
    RenderText:renderUtf8Text(bb, x, y+self._height*0.7, self.face, self.text, true, self.bold,
                self.fgcolor, self.max_width and self.max_width or self.width)
end

function TextWidget:free()
    if self._bb then
        self._bb:free()
        self._bb = nil
    end
end

return TextWidget
