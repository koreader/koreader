--[[--
A TextWidget puts a string on a single line.

Example:

    UIManager:show(TextWidget:new{
        text = "Make it so.",
        face = Font:getFace("cfont"),
        bold = true,
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    })

--]]

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Math = require("optmath")
local RenderText = require("ui/rendertext")
local Size = require("ui/size")
local Widget = require("ui/widget/widget")
local Screen = require("device").screen
local util = require("util")

local TextWidget = Widget:new{
    text = nil,
    face = nil,
    bold = false, -- synthetized/fake bold (use a bold face for nicer bold)
    fgcolor = Blitbuffer.COLOR_BLACK,
    padding = Size.padding.small, -- vertical padding (should it be function of face.size ?)
                                  -- (no horizontal padding is added)
    max_width = nil,
    truncate_with_ellipsis = true, -- when truncation at max_width needed, add "…"
    truncate_left = false, -- truncate on the right by default

    _updated = nil,
    _text_to_draw = nil,
    _length = 0,
    _height = 0,
    _baseline_h = 0,
    _maxlength = 1200,
}

function TextWidget:updateSize()
    if self._updated then
        return
    end
    self._updated = true

    -- In case we draw truncated text, keep original self.text
    -- so caller can fetch it again
    self._text_to_draw = self.text

    -- Note: we use kerning=true in all RenderText calls
    --- @todo Don't use kerning for monospaced fonts. (houqp)

    -- Compute width:
    -- We never need to draw/size more than one screen width, so limit computation
    -- to that width in case we are given some huge string
    local tsize = RenderText:sizeUtf8Text(0, Screen:getWidth(), self.face, self._text_to_draw, true, self.bold)
    -- As text length includes last glyph pen "advance" (for positionning
    -- next char), it's best to use math.floor() instead of math.ceil()
    -- to get rid of a fraction of it in case this text is to be
    -- horizontally centered
    self._length = math.floor(tsize.x)

    -- Ensure max_width, and truncate text if needed
    if self.max_width and self._length > self.max_width then
        if self.truncate_left then
            -- We want to truncate text on the left, so work with the reverse of text.
            -- We don't use kerning in this measurement as it might be different
            -- on the reversed text. The final text will use kerning, and might get
            -- a smaller width than the one found out here.
            -- Also, not sure if this is correct when diacritics/clustered glyphs
            -- happen at truncation point. But it will do for now.
            local reversed_text = util.utf8Reverse(self._text_to_draw)
            if self.truncate_with_ellipsis then
                reversed_text = RenderText:truncateTextByWidth(reversed_text, self.face, self.max_width, false, self.bold)
            else
                reversed_text = RenderText:getSubTextByWidth(reversed_text, self.face, self.max_width, false, self.bold)
            end
            self._text_to_draw = util.utf8Reverse(reversed_text)
        elseif self.truncate_with_ellipsis then
            self._text_to_draw = RenderText:truncateTextByWidth(self._text_to_draw, self.face, self.max_width, true, self.bold)
        end
        -- Get the adjusted width when limiting to max_width (it might be
        -- smaller than max_width when dropping the truncated glyph).
        tsize = RenderText:sizeUtf8Text(0, self.max_width, self.face, self._text_to_draw, true, self.bold)
        self._length = math.floor(tsize.x)
    end

    -- Compute height:
    -- Used to be:
    --   self._height = math.ceil(self.face.size * 1.5)
    --   self._baseline_h = self._height*0.7
    -- But better compute baseline alignment from freetype font metrics
    -- to get better vertical centering of text in box
    -- (Freetype doc on this at https://www.freetype.org/freetype2/docs/tutorial/step2.html)
    local face_height, face_ascender = self.face.ftface:getHeightAndAscender()
    self._height = math.ceil(face_height) + 2*self.padding
    self._baseline_h = Math.round(face_ascender) + self.padding
    -- With our UI fonts, this usually gives 0.72 to 0.74, so text is aligned
    -- a bit lower than before with the hardcoded 0.7
    -- require("logger").warn("1.5*face.size:", self.face.size * 1.5, "face_height:", face_height, "self._height:", self._height)
    -- require("logger").warn("self._height ratio:", 1.0*self._baseline_h/self._height)
end

function TextWidget:getSize()
    self:updateSize()
    return Geom:new{
        w = self._length,
        h = self._height,
    }
end

function TextWidget:getWidth()
    self:updateSize()
    return self._length
end

function TextWidget:getBaseline()
    self:updateSize()
    return self._baseline_h
end

function TextWidget:setText(text)
    self.text = text
    self._updated = false
end

function TextWidget:setMaxWidth(max_width)
    self.max_width = max_width
    self._updated = false
end

function TextWidget:paintTo(bb, x, y)
    self:updateSize()
    RenderText:renderUtf8Text(bb, x, y+self._baseline_h, self.face, self._text_to_draw, true, self.bold,
                self.fgcolor, self._length)
end

return TextWidget
