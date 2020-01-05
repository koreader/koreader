--[[--
Font module.
]]

local is_android = pcall(require, "android")

local FontList = require("fontlist")
local Freetype = require("ffi/freetype")
local Screen = require("device").screen
local logger = require("logger")

local Font = {
    fontmap = {
        -- default font for menu contents
        cfont = "NotoSans-Regular.ttf",
        -- default font for title
        --tfont = "NimbusSanL-BoldItal.cff",
        tfont = "NotoSans-Bold.ttf",
        smalltfont = "NotoSans-Bold.ttf",
        x_smalltfont = "NotoSans-Bold.ttf",
        -- default font for footer
        ffont = "NotoSans-Regular.ttf",
        smallffont = "NotoSans-Regular.ttf",
        largeffont = "NotoSans-Regular.ttf",

        -- default font for reading position info
        rifont = "NotoSans-Regular.ttf",

        -- default font for pagination display
        pgfont = "NotoSans-Regular.ttf",

        -- selectmenu: font for item shortcut
        scfont = "DroidSansMono.ttf",

        -- help page: font for displaying keys
        hpkfont = "DroidSansMono.ttf",
        -- font for displaying help messages
        hfont = "NotoSans-Regular.ttf",

        -- font for displaying input content
        -- we have to use mono here for better distance controlling
        infont = "DroidSansMono.ttf",
        -- small mono font for displaying code
        smallinfont = "DroidSansMono.ttf",

        -- font for info messages
        infofont = "NotoSans-Regular.ttf",

        -- small font for info messages
        smallinfofont = "NotoSans-Regular.ttf",
        -- small bold font for info messages
        smallinfofontbold = "NotoSans-Bold.ttf",
        -- extra small font for info messages
        x_smallinfofont = "NotoSans-Regular.ttf",
        -- extra extra small font for info messages
        xx_smallinfofont = "NotoSans-Regular.ttf",
    },
    sizemap = {
        cfont = 24,
        tfont = 26,
        smalltfont = 24,
        x_smalltfont = 22,
        ffont = 20,
        smallffont = 15,
        largeffont = 25,
        pgfont = 20,
        scfont = 20,
        rifont = 16,
        hpkfont = 20,
        hfont = 24,
        infont = 22,
        smallinfont = 16,
        infofont = 24,
        smallinfofont = 22,
        smallinfofontbold = 22,
        x_smallinfofont = 20,
        xx_smallinfofont = 18,
    },
    fallbacks = {
        [1] = "NotoSans-Regular.ttf",
        [2] = "NotoSansCJKsc-Regular.otf",
        [3] = "NotoSansArabicUI-Regular.ttf",
        [4] = "nerdfonts/symbols.ttf",
        [5] = "freefont/FreeSans.ttf",
        [6] = "freefont/FreeSerif.ttf",
    },

    -- face table
    faces = {},
}

if is_android then
    table.insert(Font.fallbacks, 3, "DroidSansFallback.ttf") -- for some ancient pre-4.4 Androids
end

-- Synthetized bold strength can be tuned:
-- local bold_strength_factor = 1   -- really too bold
-- local bold_strength_factor = 1/2 -- bold enough
local bold_strength_factor = 3/8 -- as crengine, lighter

-- Callback to be used by libkoreader-xtext.so to get Freetype
-- instantiated fallback fonts when needed for shaping text
local _getFallbackFont = function(face_obj, num)
    if not num or num == 0 then -- return the main font
        if not face_obj.embolden_half_strength then
            -- cache this value in case we use bold, to avoid recomputation
            face_obj.embolden_half_strength = face_obj.ftface:getEmboldenHalfStrength(bold_strength_factor)
        end
        return face_obj
    end
    if not face_obj.fallbacks then
        face_obj.fallbacks = {}
    end
    if face_obj.fallbacks[num] ~= nil then
        return face_obj.fallbacks[num]
    end
    local next_num = #face_obj.fallbacks + 1
    local cur_num = 0
    for index, fontname in pairs(Font.fallbacks) do
        if fontname ~= face_obj.realname then -- Skip base one if among fallbacks
            local fb_face = Font:getFace(fontname, face_obj.orig_size)
            if fb_face ~= nil then -- valid font
                cur_num = cur_num + 1
                if cur_num == next_num then
                    face_obj.fallbacks[next_num] = fb_face
                    if not fb_face.embolden_half_strength then
                        fb_face.embolden_half_strength = fb_face.ftface:getEmboldenHalfStrength(bold_strength_factor)
                    end
                    return fb_face
                end
            end
        end
    end
    -- no more fallback font
    face_obj.fallbacks[next_num] = false
    return false
end

--- Gets font face object.
-- @string font
-- @int size optional size
-- @treturn table @{FontFaceObj}
function Font:getFace(font, size)
    -- default to content font
    if not font then font = self.cfont end

    if not size then size = self.sizemap[font] end
    -- original size before scaling by screen DPI
    local orig_size = size
    size = Screen:scaleBySize(size)

    local hash = font..size
    local face_obj = self.faces[hash]
    -- build face if not found
    if not face_obj then
        local realname = self.fontmap[font]
        if not realname then
            realname = font
        end
        local builtin_font_location = FontList.fontdir.."/"..realname
        local ok, face = pcall(Freetype.newFace, builtin_font_location, size)

        -- Not all fonts are bundled on all platforms because they come with the system.
        -- In that case, search through all font folders for the requested font.
        if not ok then
            local fonts = FontList:getFontList()
            local escaped_realname = realname:gsub("[-]", "%%-")

            for _k, _v in ipairs(fonts) do
                if _v:find(escaped_realname) then
                    logger.dbg("Found font:", realname, "in", _v)
                    ok, face = pcall(Freetype.newFace, _v, size)

                    if ok then break end
                end
            end
        end
        if not ok then
            logger.err("#! Font ", font, " (", realname, ") not supported: ", face)
            return nil
        end
        --- Freetype font face wrapper object
        -- @table FontFaceObj
        -- @field orig_font font name requested
        -- @field size size of the font face (after scaled by screen size)
        -- @field orig_size raw size of the font face (before scale)
        -- @field ftface font face object from freetype
        -- @field hash hash key for this font face
        face_obj = {
            orig_font = font,
            realname = realname,
            size = size,
            orig_size = orig_size,
            ftface = face,
            hash = hash,
        }
        self.faces[hash] = face_obj

        -- Callback to be used by libkoreader-xtext.so to get Freetype
        -- instantiated fallback fonts when needed for shaping text
        face_obj.getFallbackFont = function(num)
            return _getFallbackFont(face_obj, num)
        end
        -- Font features, to be given by libkoreader-xtext.so to HarfBuzz.
        -- (Could be tweaked by font if needed. Note that NotoSans does not
        -- have common ligatures, like for "fi" or "fl", so we won't see
        -- them in the UI.)
        -- Use HB defaults, and be sure to enable kerning and ligatures
        -- (which might be part of HB defaults, or not, not sure).
        face_obj.hb_features = { "+kern", "+liga" }
        -- If we'd wanted to disable all features that might be enabled
        -- by HarfBuzz (see harfbuzz/src/hb-ot-shape.cc, quite unclear
        -- what's enabled or not by default):
        -- face_obj.hb_features = {
        --      "-kern", "-mark", "-mkmk", "-curs", "-locl", "-liga",
        --      "-rlig", "-clig", "-ccmp", "-calt", "-rclt", "-rvrn",
        --      "-ltra", "-ltrm", "-rtla", "-rtlm", "-frac", "-numr",
        --      "-dnom", "-rand", "-trak", "-vert", }
    end
    return face_obj
end

return Font
