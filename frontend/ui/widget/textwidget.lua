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
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Math = require("optmath")
local RenderText = require("ui/rendertext")
local Size = require("ui/size")
local Widget = require("ui/widget/widget")
local Screen = require("device").screen
local dbg = require("dbg")
local util = require("util")

local TextWidget = Widget:new{
    text = nil,
    face = nil,
    bold = false, -- use bold=true to use a real bold font (or synthetized if not available),
                  -- or bold=Font.FORCE_SYNTHETIZED_BOLD to force using synthetized bold,
                  -- which, with XText, makes a bold string the same width as it non-bolded.
    fgcolor = Blitbuffer.COLOR_BLACK,
    padding = Size.padding.small, -- vertical padding (should it be function of face.size ?)
                                  -- (no horizontal padding is added)
    max_width = nil,
    truncate_with_ellipsis = true, -- when truncation at max_width needed, add "…"
    truncate_left = false, -- truncate on the right by default

    -- Force a baseline and height to use instead of those obtained from the font used
    -- (mostly only useful for TouchMenu to display font names in their own font, to
    -- ensure they get correctly vertically aligned in the menu)
    forced_baseline = nil,
    forced_height = nil,

    -- for internal use
    _updated = nil,
    _face_adjusted = nil,
    _text_to_draw = nil,
    _length = 0,
    _height = 0,
    _baseline_h = 0,
    _maxlength = 1200,
    _is_truncated = nil,

    -- Additional properties only used when using xtext
    use_xtext = G_reader_settings:nilOrTrue("use_xtext"),
    lang = nil, -- use this language (string) instead of the UI language
    para_direction_rtl = nil, -- use true/false to override the default direction for the UI language
    auto_para_direction = false, -- detect direction of each paragraph in text
                                 -- (para_direction_rtl or UI language is then only
                                 -- used as a weak hint about direction)
    _xtext = nil, -- for internal use
    _xshaping = nil,
}

-- Helper function to be used before instantiating a TextWidget instance
-- (This is more precise than the one with the same name in TextBoxWidget,
-- as we use the real font metrics.)
function TextWidget:getFontSizeToFitHeight(font_name, height_px, padding)
    -- Get a font size that would fit the text in height_px.
    if not padding then
        padding = self.padding -- (TextWidget default above: Size.padding.small)
    end
    -- We need to iterate (skip 1 early as font_size is always smaller
    -- than font height)
    local font_size = height_px
    repeat
        font_size = font_size - 1
        if font_size <= 1 then
            break
        end
        local face = Font:getFace(font_name, font_size)
        local face_height = face.ftface:getHeightAndAscender()
        face_height = math.ceil(face_height) + 2*padding
    until face_height <= height_px
    return font_size
end

function TextWidget:updateSize()
    if self._updated then
        return
    end
    self._updated = true

    if not self._face_adjusted then
        self._face_adjusted = true -- only do that once
        -- If self.bold, or if self.face is a real bold face, we may need to use
        -- an alternative instance of self.face, with possibly the associated
        -- real bold font, and/or with tweaks so fallback fonts are rendered bold
        -- too, without affecting the regular self.face
        self.face, self.bold = Font:getAdjustedFace(self.face, self.bold)
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

    if self.text and type(self.text) ~= "string" then
        self.text = tostring(self.text)
    end
    self._is_empty = false
    if not self.text or #self.text == 0 then
        self._is_empty = true
        self._length = 0
        return
    end
    self._is_truncated = false

    -- Compute width:
    if self.use_xtext then
        self:_measureWithXText()
        return
    end

    -- Only when not self.use_xtext:

    -- Note: we use kerning=true in all RenderText calls
    -- (But kerning should probably not be used with monospaced fonts.)

    -- In case we draw truncated text, keep original self.text
    -- so caller can fetch it again
    self._text_to_draw = self.text

    -- We never need to draw/size more than one screen width, so limit computation
    -- to that width in case we are given some huge string
    local tsize = RenderText:sizeUtf8Text(0, Screen:getWidth(), self.face, self._text_to_draw, true, self.bold)
    -- As text length includes last glyph pen "advance" (for positioning
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
        self._is_truncated = true
    end
end
dbg:guard(TextWidget, "updateSize",
    function(self)
        assert(type(self.text) == "string",
            "Wrong text type (expected string)")
    end)

function TextWidget:_measureWithXText()
    if not self._xtext_loaded then
        require("libs/libkoreader-xtext")
        TextWidget._xtext_loaded = true
    end
    self._xtext = xtext.new(self.text, self.face, self.auto_para_direction,
                                            self.para_direction_rtl, self.lang)
    self._xtext:measure()
    self._length = self._xtext:getWidth()
    self._xshaping = nil

    -- Segment of self._xtext to shape and draw: all of it if no max_width
    self._shape_start = 1
    self._shape_end = #self._xtext
    self._shape_idx_to_substitute_with_ellipsis = nil

    -- Ensure max_width: find a segment that fit
    if self.max_width and self._length > self.max_width then
        local line_start = 1
        local reserved_width = 0
        if self.truncate_with_ellipsis then
            -- Get the width of an ellipsis from FreeType. It might then be
            -- larger than the shaped glyph we'll get from xtext/HarfBuzz,
            -- but we should be fine by the diff. Hoping both FreeType and
            -- xtext will use the same fallback font if not found in the
            -- specified font.
            -- (If needed, have a callback in the font table that will create
            -- a TextWidget, with use_xtext, to have it compute the width of
            -- the ellipsis, and then cache this width in the font table.)
            reserved_width = RenderText:getEllipsisWidth(self.face)
                -- no bold: xtext does synthetized bold with normal metrics
        end
        local max_width = self.max_width - reserved_width
        if max_width <= 0 then -- avoid _xtext:makeLine() crash
            max_width = self.max_width
        end
        if self.truncate_left then
            line_start = self._xtext:getSegmentFromEnd(max_width)
        end
        local line = self._xtext:makeLine(line_start, max_width, true) -- no_line_breaking_rules=true
        self._shape_start = line.offset
        self._shape_end = line.end_offset
        self._length = line.width + reserved_width -- might end up being smaller than max_width
        if self.truncate_with_ellipsis then
            if self.truncate_left and self._shape_start > 1 then
                self._shape_start = self._shape_start - 1
                self._shape_idx_to_substitute_with_ellipsis = self._shape_start
            elseif self._shape_end < #self._xtext then
                self._shape_end = self._shape_end + 1
                self._shape_idx_to_substitute_with_ellipsis = self._shape_end
            end
        end
        self._is_truncated = true
    end
end

-- Returns the substring of text that fits in self.max_width
-- The substring does not include the ellipsis that could
-- be added when drawn.
-- 2nd returned value is nil if no truncation, false when truncated
-- and no ellipsis would be added, true if truncated and an ellipsis
-- will be added (on the right or left of string in logical order,
-- caller knows the side from the provided 'truncate_left').
function TextWidget:getFittedText()
    if not self.max_width then
        return self.text, nil
    end
    self:updateSize()
    if self._is_empty then
        return "", nil
    end
    if not self.use_xtext then
        if self._text_to_draw == self.text then
            return self.text, nil
        end
        if not self.truncate_with_ellipsis then
            return self._text_to_draw, false
        end
        -- ellipsis is 3 bytes
        if self.truncate_left then
            return self._text_to_draw:sub(3), true
        else
            return self._text_to_draw:sub(1, -4), true
        end
    end
    if self._shape_start == 1 and self._shape_end == #self.text then
        -- not truncated
        return self.text, nil
    end
    local with_ellipsis = false
    local start_idx, end_idx = self._shape_start, self._shape_end
    if self._shape_idx_to_substitute_with_ellipsis then
        with_ellipsis = true
        if self.truncate_left then
            start_idx = start_idx + 1
        else
            end_idx = end_idx - 1
        end
    end
    -- These start and end indexes are in the internal unicode
    -- string of the xtext object, and we can't use them as
    -- indices of the UTF-8 self.text.
    -- So, get the UTF-8 directly from xtext.
    local text = self._xtext:getText(start_idx, end_idx)
    return text, with_ellipsis
end

function TextWidget:getSize()
    self:updateSize()
    return Geom:new{
        w = self._length,
        h = self.forced_height or self._height,
    }
end

function TextWidget:getWidth()
    self:updateSize()
    return self._length
end

function TextWidget:isTruncated()
    self:updateSize()
    return self._is_truncated
end

function TextWidget:getBaseline()
    self:updateSize()
    return self._baseline_h
end

function TextWidget:setText(text)
    if text ~= self.text then
        self.text = text
        self:free()
    end
end
dbg:guard(TextWidget, "setText",
    function(self, text)
        assert(type(text) == "string",
            "Wrong text type (expected string)")
    end)

function TextWidget:setMaxWidth(max_width)
    if max_width ~= self.max_width then
        self.max_width = max_width
        self:free()
    end
end

function TextWidget:paintTo(bb, x, y)
    self:updateSize()
    if self._is_empty then
        return
    end

    if not self.use_xtext then
        RenderText:renderUtf8Text(bb, x, y+self._baseline_h, self.face, self._text_to_draw,
                                true, self.bold, self.fgcolor, self._length)
        return
    end

    -- Draw shaped glyphs with the help of xtext
    if not self._xshaping then
        self._xshaping = self._xtext:shapeLine(self._shape_start, self._shape_end,
                                            self._shape_idx_to_substitute_with_ellipsis)
    end

    -- Don't draw outside of BlitBuffer or max_width
    local text_width = bb:getWidth() - x
    if self.max_width and self.max_width < text_width then
        text_width = self.max_width
    end
    local pen_x = 0
    local baseline = self.forced_baseline or self._baseline_h
    for i, xglyph in ipairs(self._xshaping) do
        if pen_x >= text_width then
            break
        end
        local face = self.face.getFallbackFont(xglyph.font_num) -- callback (not a method)
        local glyph = RenderText:getGlyphByIndex(face, xglyph.glyph, self.bold)
        bb:colorblitFrom(
            glyph.bb,
            x + pen_x + glyph.l + xglyph.x_offset,
            y + baseline - glyph.t - xglyph.y_offset,
            0, 0,
            glyph.bb:getWidth(), glyph.bb:getHeight(),
            self.fgcolor)
        pen_x = pen_x + xglyph.x_advance -- use Harfbuzz advance
    end
end

function TextWidget:free()
    --print("TextWidget:free on", self)
    -- Allow not waiting until Lua gc() to cleanup C XText malloc'ed stuff
    if self._xtext then
        self._xtext:free()
        self._xtext = nil
    end
    self._updated = false
end

function TextWidget:onCloseWidget()
    -- Free _xtext when UIManager closes this widget (as it won't
    -- be painted anymore).
    self:free()
end

return TextWidget
