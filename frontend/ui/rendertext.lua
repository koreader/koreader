--[[--
Text rendering module.
]]

local Font = require("ui/font")
local Cache = require("cache")
local CacheItem = require("cacheitem")
local BlitBuffer = require("ffi/blitbuffer")
local logger = require("logger")

if require("device"):isAndroid() then
    require("jit").off(true, true)
end

--[[
@TODO: all these functions should probably be methods on Face objects
]]--
local RenderText = {}

local GlyphCache = Cache:new{
    max_memsize = 512*1024,
    current_memsize = 0,
    cache = {},
    -- this will hold the LRU order of the cache
    cache_order = {}
}

-- iterator over UTF8 encoded characters in a string
local function utf8Chars(input_text)
    local function read_next_glyph(input, pos)
        if string.len(input) < pos then return nil end
        local value = string.byte(input, pos)
        if bit.band(value, 0x80) == 0 then
            -- TODO: check valid ranges
            return pos+1, value, string.sub(input, pos, pos)
        elseif bit.band(value, 0xC0) == 0x80 -- invalid, continuation
        or bit.band(value, 0xF8) == 0xF8 -- 5-or-more byte sequence, illegal due to RFC3629
        then
            return pos+1, 0xFFFD, "\xFF\xFD"
        else
            local glyph, bytes_left
            if bit.band(value, 0xE0) == 0xC0 then
                glyph = bit.band(value, 0x1F)
                bytes_left = 1
            elseif bit.band(value, 0xF0) == 0xE0 then
                glyph = bit.band(value, 0x0F)
                bytes_left = 2
            elseif bit.band(value, 0xF8) == 0xF0 then
                glyph = bit.band(value, 0x07)
                bytes_left = 3
            else
                return pos+1, 0xFFFD, "\xFF\xFD"
            end
            if string.len(input) < (pos + bytes_left) then
                return pos+1, 0xFFFD, "\xFF\xFD"
            end
            for i = pos+1, pos + bytes_left do
                value = string.byte(input, i)
                if bit.band(value, 0xC0) == 0x80 then
                    glyph = bit.bor(bit.lshift(glyph, 6), bit.band(value, 0x3F))
                else
                    -- invalid UTF8 continuation - don't be greedy, just skip
                    -- the initial char of the sequence.
                    return pos+1, 0xFFFD, "\xFF\xFD"
                end
            end
            -- TODO: check for valid ranges here!
            return pos+bytes_left+1, glyph, string.sub(input, pos, pos+bytes_left)
        end
    end
    return read_next_glyph, input_text, 1
end

--- Returns a rendered glyph
--
-- @tparam ui.font.FontFaceObj face font face for the text
-- @int charcode
-- @bool[opt=false] bold whether the text should be measured as bold
-- @treturn glyph
function RenderText:getGlyph(face, charcode, bold)
    local hash = "glyph|"..face.hash.."|"..charcode.."|"..(bold and 1 or 0)
    local glyph = GlyphCache:check(hash)
    if glyph then
        -- cache hit
        return glyph[1]
    end
    local rendered_glyph = face.ftface:renderGlyph(charcode, bold)
    if face.ftface:checkGlyph(charcode) == 0 then
        for index, font in pairs(Font.fallbacks) do
            -- use original size before scaling by screen DPI
            local fb_face = Font:getFace(font, face.orig_size)
            if fb_face ~= nil then
            -- for some characters it cannot find in Fallbacks, it will crash here
                if fb_face.ftface:checkGlyph(charcode) ~= 0 then
                    rendered_glyph = fb_face.ftface:renderGlyph(charcode, bold)
                    break
                end
            end
        end
    end
    if not rendered_glyph then
        logger.warn("error rendering glyph (charcode=", charcode, ") for face", face)
        return
    end
    glyph = CacheItem:new{rendered_glyph}
    glyph.size = glyph[1].bb:getWidth() * glyph[1].bb:getHeight() / 2 + 32
    GlyphCache:insert(hash, glyph)
    return rendered_glyph
end

--- Returns a substring of a given text that meets the maximum width (in pixels)
-- restriction.
--
-- @string text text to truncate
-- @tparam ui.font.FontFaceObj face font face for the text
-- @int width maximum width in pixels
-- @bool[opt=false] kerning whether the text should be measured with kerning
-- @bool[opt=false] bold whether the text should be measured as bold
-- @treturn string
-- @see truncateTextByWidth
function RenderText:getSubTextByWidth(text, face, width, kerning, bold)
    local pen_x = 0
    local prevcharcode
    local char_list = {}
    for _, charcode, uchar in utf8Chars(text) do
        if pen_x < width then
            local glyph = self:getGlyph(face, charcode, bold)
            if kerning and prevcharcode then
                local kern = face.ftface:getKerning(prevcharcode, charcode)
                pen_x = pen_x + kern
            end
            pen_x = pen_x + glyph.ax
            if pen_x <= width then
                prevcharcode = charcode
                table.insert(char_list, uchar)
            else
                break
            end
        end
    end
    return table.concat(char_list)
end

--- Measure rendered size for a given text.
--
-- Note this function does not render the text into a bitmap. Use it if you
-- only need the estimated size information.
--
-- @int x start position for a given text (within maximum width)
-- @int width maximum rendering width in pixels (think of it as size of the bitmap)
-- @tparam ui.font.FontFaceObj face font face that will be used for rendering
-- @string text text to measure
-- @bool[opt=false] kerning whether the text should be measured with kerning
-- @bool[opt=false] bold whether the text should be measured as bold
-- @treturn RenderTextSize
function RenderText:sizeUtf8Text(x, width, face, text, kerning, bold)
    if not text then
        logger.warn("sizeUtf8Text called without text");
        return
    end

    -- may still need more adaptive pen placement when kerning,
    -- see: http://freetype.org/freetype2/docs/glyphs/glyphs-4.html
    local pen_x = 0
    local pen_y_top = 0
    local pen_y_bottom = 0
    local prevcharcode = 0
    for _, charcode, uchar in utf8Chars(text) do
        if pen_x < (width - x) then
            local glyph = self:getGlyph(face, charcode, bold)
            if kerning and (prevcharcode ~= 0) then
                pen_x = pen_x + (face.ftface):getKerning(prevcharcode, charcode)
            end
            pen_x = pen_x + glyph.ax
            pen_y_top = math.max(pen_y_top, glyph.t)
            pen_y_bottom = math.max(pen_y_bottom, glyph.bb:getHeight() - glyph.t)
            prevcharcode = charcode
        end -- if pen_x < (width - x)
    end

    --- RenderText size information
    -- @table RenderTextSize
    -- @field x length of the text on x coordinate
    -- @field y_top distance between top-most pixel (scanline) and baseline
    -- (bearingY)
    -- @field y_bottom distance between bottom-most pixel (scanline) and
    -- baseline (height - y_top)
    return { x = pen_x, y_top = pen_y_top, y_bottom = pen_y_bottom }
end

--- Render a given text into a given BlitBuffer
--
-- @tparam BlitBuffer dest_bb Buffer to blit into
-- @int x starting x coordinate position within dest_bb
-- @int baseline y coordinate for baseline, within dest_bb
-- @tparam ui.font.FontFaceObj face font face that will be used for rendering
-- @string text text to render
-- @bool[opt=false] kerning whether the text should be measured with kerning
-- @bool[opt=false] bold whether the text should be measured as bold
-- @tparam[opt=BlitBuffer.COLOR_BLACK] BlitBuffer.COLOR fgcolor foreground color
-- @int[opt=nil] width maximum rendering width
-- @tparam[opt] table char_pads array of integers, nb of pixels to add, one for each utf8 char in text
-- @return int width of rendered bitmap
function RenderText:renderUtf8Text(dest_bb, x, baseline, face, text, kerning, bold, fgcolor, width, char_pads)
    if not text then
        logger.warn("renderUtf8Text called without text");
        return 0
    end

    if not fgcolor then
        fgcolor = BlitBuffer.COLOR_BLACK
    end

    -- may still need more adaptive pen placement when kerning,
    -- see: http://freetype.org/freetype2/docs/glyphs/glyphs-4.html
    local pen_x = 0
    local prevcharcode = 0
    local text_width = dest_bb:getWidth() - x
    if width and width < text_width then
        text_width = width
    end
    local char_idx = 0
    for _, charcode, uchar in utf8Chars(text) do
        if pen_x < text_width then
            local glyph = self:getGlyph(face, charcode, bold)
            if kerning and (prevcharcode ~= 0) then
                pen_x = pen_x + face.ftface:getKerning(prevcharcode, charcode)
            end
            dest_bb:colorblitFrom(
                glyph.bb,
                x + pen_x + glyph.l,
                baseline - glyph.t,
                0, 0,
                glyph.bb:getWidth(), glyph.bb:getHeight(),
                fgcolor)
            pen_x = pen_x + glyph.ax
            prevcharcode = charcode
        end -- if pen_x < text_width
        if char_pads then
            char_idx = char_idx + 1
            pen_x = pen_x + char_pads[char_idx] -- or 0
            -- will fail if we didnt count the same number of chars, we'll see
        end
    end

    return pen_x
end

local ellipsis, space = "…", " "
local ellipsis_width, space_width
--- Returns a substring of a given text that meets the maximum width (in pixels)
-- restriction with ellipses (…) at the end if required.
--
-- @string text text to truncate
-- @tparam ui.font.FontFaceObj face font face for the text
-- @int width maximum width in pixels
-- @bool[opt=false] kerning whether the text should be measured with kerning
-- @bool[opt=false] bold whether the text should be measured as bold
-- @bool[opt=false] prepend_space whether a space should be prepended to the text
-- @treturn string
-- @see getSubTextByWidth
function RenderText:truncateTextByWidth(text, face, max_width, kerning, bold, prepend_space)
    if not ellipsis_width then
        ellipsis_width = self:sizeUtf8Text(0, max_width, face, ellipsis).x
    end
    if not space_width then
        space_width = self:sizeUtf8Text(0, max_width, face, space).x
    end
    local new_txt_width = max_width - ellipsis_width - space_width
    local sub_txt = self:getSubTextByWidth(text, face, new_txt_width, kerning, bold)
    if prepend_space then
        return space.. sub_txt .. ellipsis
    else
        return sub_txt .. ellipsis .. space
    end
end

return RenderText
