--[[--
Font module.
]]

local FontList = require("fontlist")
local Freetype = require("ffi/freetype")
local Screen = require("device").screen
local logger = require("logger")
local util = require("util")

-- Known regular (and italic) fonts with an available bold font file
local _bold_font_variant = {}
_bold_font_variant["NotoSans-Regular.ttf"] = "NotoSans-Bold.ttf"
_bold_font_variant["NotoSans-Italic.ttf"] = "NotoSans-BoldItalic.ttf"
_bold_font_variant["NotoSansArabicUI-Regular.ttf"] = "NotoSansArabicUI-Bold.ttf"
_bold_font_variant["NotoSerif-Regular.ttf"] = "NotoSerif-Bold.ttf"
_bold_font_variant["NotoSerif-Italic.ttf"] = "NotoSerif-BoldItalic.ttf"

-- Build the reverse mapping, so we can know a font is bold
local _regular_font_variant = {}
for regular, bold in pairs(_bold_font_variant) do
    _regular_font_variant[bold] = regular
end

local Font = {
    -- Make these available in the Font object, so other code
    -- can complete them if needed.
    bold_font_variant = _bold_font_variant,
    regular_font_variant = _regular_font_variant,

    -- Allow globally not promoting fonts to their bold variants
    -- (and use thinner and narrower synthesized bold instead).
    use_bold_font_for_bold = G_reader_settings:nilOrTrue("use_bold_font_for_bold"),

    -- Widgets can provide "bold = Font.FORCE_SYNTHETIZED_BOLD" instead
    -- of "bold = true" to explicitly request synthesized bold, which,
    -- with XText, makes a bold string the same width as itself non-bold.
    FORCE_SYNTHETIZED_BOLD = "FORCE_SYNTHETIZED_BOLD",

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
    -- This fallback fonts list should only contain
    -- regular weight (non bold) font files.
    fallbacks = {
        [1] = "NotoSans-Regular.ttf",
        [2] = "NotoSansCJKsc-Regular.otf",
        [3] = "NotoSansArabicUI-Regular.ttf",
        [4] = "NotoSansDevanagariUI-Regular.ttf",
        [5] = "NotoSansBengaliUI-Regular.ttf",
        [6] = "nerdfonts/symbols.ttf",
        [7] = "freefont/FreeSans.ttf",
        [8] = "freefont/FreeSerif.ttf",
    },
    -- Additional fallback fonts are managed by frontend/ui/elements/font_ui_fallbacks.lua
    -- Add any after NotoSansCJKsc (because CJKsc has better symbols, and has 'locl' OTF
    -- features to support all of SC, TC, JA and KO that other CJK fonts may not have.)
    additional_fallback_insert_indice = 3,
    -- Xtext supports up to 15 fallback fonts, but keep some slots free and available for
    -- future additions to our hardcoded fallbacks list above, and to not slow down
    -- rendering with too many fallback fonts.
    additional_fallback_max_nb = 4,

    -- face table
    faces = {},
}

if G_reader_settings and G_reader_settings:has("font_ui_fallbacks") then
    local additional_fallbacks = G_reader_settings:readSetting("font_ui_fallbacks")
    for i=#additional_fallbacks, 1, -1 do
        table.insert(Font.fallbacks, Font.additional_fallback_insert_indice, additional_fallbacks[i])
    end
    logger.dbg("updated Font.fallbacks:", Font.fallbacks)
end

-- We don't ship a bold variant for some of our fallback fonts.
-- Allow users themselves to drop a Noto Sans Bold variant of their most used fallbacks,
-- and we will use them if present.
-- Match bold font to fallback by name. We do not use FontInfo name match
-- to allow users more flexibility.
-- Because the hardcoded fallback fonts' paths are their filenames not actual paths,
-- we need to match with filenames rather than paths
local bold_candidates = {} -- key: bold font's name, value: corresponding regular font's path
for _, fallback_font_path in ipairs(Font.fallbacks) do
    local _, font_name = util.splitFilePathName(fallback_font_path)
    if font_name and not _bold_font_variant[fallback_font_path]
                 and not _bold_font_variant[font_name]
                 and font_name:find("-Regular") then
        local bold_font_name = font_name:gsub("-Regular", "-Bold", 1, true)
        bold_candidates[bold_font_name] = fallback_font_path
    end
end

for _, font_path in ipairs(FontList:getFontList()) do
    local _, bold_font_name = util.splitFilePathName(font_path)
    local fallback_font_path = bold_candidates[bold_font_name]
    if bold_font_name and fallback_font_path then
        Font.bold_font_variant[fallback_font_path] = font_path
        Font.regular_font_variant[font_path] = fallback_font_path
        bold_candidates[bold_font_name] = nil
    end
    if #bold_candidates == 0 then
        break
    end
end
bold_candidates = nil -- luacheck: ignore

-- Helper functions with explicit names around
-- bold/regular_font_variant tables
function Font:hasBoldVariant(name)
    return self.bold_font_variant[name] and true or false
end

function Font:getBoldVariantName(name)
    return self.bold_font_variant[name]
end

function Font:isRealBoldFont(name)
    return self.regular_font_variant[name] and true or false
end

function Font:getRegularVariantName(name)
    return self.regular_font_variant[name] or name
end

-- Synthesized bold strength can be tuned:
-- local bold_strength_factor = 1   -- really too bold
-- local bold_strength_factor = 1/2 -- bold enough
local bold_strength_factor = 3/8 -- as crengine, lighter

-- Add some properties to a face object as needed
local _completeFaceProperties = function(face_obj)
    if not face_obj.embolden_half_strength then
        -- Cache this value in case we use bold, to avoid recomputation
        face_obj.embolden_half_strength = face_obj.ftsize:getEmboldenHalfStrength(bold_strength_factor)
    end
end

-- Callback to be used by libkoreader-xtext.so to get Freetype
-- instantiated fallback fonts when needed for shaping text
-- (Beware: any error in this code won't be noticed when this
-- is called from the C module...)
local _getFallbackFont = function(face_obj, num)
    if not num or num == 0 then -- return the main font
        _completeFaceProperties(face_obj)
        return face_obj
    end
    if not face_obj.fallbacks then
        face_obj.fallbacks = {}
    end
    if face_obj.fallbacks[num] ~= nil then -- (false means: no more fallback font)
        return face_obj.fallbacks[num]
    end
    local next_num = #face_obj.fallbacks + 1
    local cur_num = 0
    local realname = face_obj.realname
    if face_obj.is_real_bold then
        -- Get the regular name, to skip it from Font.fallbacks
        realname = Font:getRegularVariantName(realname)
    end
    for index, fontname in pairs(Font.fallbacks) do
        if fontname ~= realname then -- Skip base one if among fallbacks
            -- If main font is a real bold, or if it's not but we want bold,
            -- get the bold variant of the fallback if one exists.
            -- But if one exists, use the regular variant as an additional
            -- fallback, drawn with synthesized bold (often, bold fonts
            -- have less glyphs than their regular counterpart).
            if face_obj.is_real_bold or face_obj.wants_bold == true then
                                -- (not if wants_bold==Font.FORCE_SYNTHETIZED_BOLD)
                local bold_variant_name = Font:getBoldVariantName(fontname)
                if bold_variant_name then
                    -- There is a bold variant of that fallback font, that we can use
                    local fb_face = Font:getFace(bold_variant_name, face_obj.orig_size)
                    if fb_face ~= nil then -- valid font
                        cur_num = cur_num + 1
                        if cur_num == next_num then
                            _completeFaceProperties(fb_face)
                            face_obj.fallbacks[next_num] = fb_face
                            return fb_face
                        end
                        -- otherwise, go on with the regular variant
                    end
                end
            end
            local fb_face = Font:getFace(fontname, face_obj.orig_size)
            if fb_face ~= nil then -- valid font
                cur_num = cur_num + 1
                if cur_num == next_num then
                    _completeFaceProperties(fb_face)
                    face_obj.fallbacks[next_num] = fb_face
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
-- @int faceindex optional index of font face in font file
-- @treturn table @{FontFaceObj}
function Font:getFace(font, size, faceindex)
    -- default to content font
    if not font then font = self.fontmap.cfont end

    if not size then size = self.sizemap[font] end
    -- original size before scaling by screen DPI
    local orig_size = size
    size = Screen:scaleBySize(size)

    local realname = self.fontmap[font]
    if not realname then
        realname = font
    end

    -- Avoid emboldening already bold fonts
    local is_real_bold = self:isRealBoldFont(realname)

    -- Make a hash from the realname (many fonts in our fontmap use
    -- the same font file: have them share their glyphs cache)
    local hash = realname..size
    if faceindex then
        hash = hash .. "/" .. faceindex
    end

    local face_obj = self.faces[hash]
    if face_obj then
        -- Font found
        if face_obj.orig_size ~= orig_size then
            -- orig_size has changed (which may happen on small orig_size variations
            -- mapping to a same final size, but more importantly when geometry
            -- or dpi has changed): keep it updated, so code that would reuse
            -- it to fetch another font get the current original font size and
            -- not one from the past
            face_obj.orig_size = orig_size
        end
    else
        -- Build face size if not found
        local builtin_font_location = FontList.fontdir.."/"..realname
        local ok, ftsize = pcall(Freetype.newFaceSize, builtin_font_location, size, faceindex)

        -- Not all fonts are bundled on all platforms because they come with the system.
        -- In that case, search through all font folders for the requested font.
        if not ok then
            local fonts = FontList:getFontList()
            local escaped_realname = realname:gsub("[-]", "%%-")

            for _k, _v in ipairs(fonts) do
                if _v:find(escaped_realname) then
                    logger.dbg("Found font:", realname, "in", _v)
                    ok, ftsize = pcall(Freetype.newFaceSize, _v, size, faceindex)

                    if ok then break end
                end
            end
        end
        if not ok then
            logger.err("#! Font ", font, " (", realname, ") not supported: ", ftsize)
            return nil
        end
        --- Freetype font face wrapper object
        -- @table FontFaceObj
        -- @field orig_font font name requested
        -- @field size size of the font face (after scaled by screen size)
        -- @field orig_size raw size of the font face (before scale)
        -- @field ftsize font size object from freetype
        -- @field hash hash key for this font face
        face_obj = {
            orig_font = font,
            realname = realname,
            size = size,
            orig_size = orig_size,
            ftsize = ftsize,
            hash = hash,
            is_real_bold = is_real_bold,
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

--- Returns an alternative face instance to be used for measuring
-- and drawing (in most cases, the one provided untouched)
--
-- If 'bold' is true, or if 'face' is a real bold face, we may need to
-- use an alternative instance of the font, with possibly the associated
-- real bold font, and/or with tweaks so fallback fonts are rendered
-- bold too, without affecting the regular 'face'.
-- (This function should only be used by TextWidget and TextBoxWidget.
-- Other widgets should not use it, and neither _getFallbackFont()
-- which will do its own processing.)
--
-- @tparam ui.font.FontFaceObj provided face font face
-- @bool bold whether bold is requested
-- @treturn ui.font.FontFaceObj face face to use for drawing
-- @treturn bool bold adjusted bold properties
function Font:getAdjustedFace(face, bold)
    if face.is_real_bold then
        -- No adjustment needed: main real bold font will ensure
        -- fallback fonts use their associated bold font or
        -- get synthesized bold - whether bold is requested or not
        -- (Set returned bold to true, to force synthesized bold
        -- on fallback fonts with no associated real bold)
        -- (Drop bold=FORCE_SYNTHETIZED_BOLD and use 'true' if
        -- we were given a real bold font.)
        return face, true
    end
    if not bold then
        -- No adjustment needed: regular main font, and regular
        -- fallback fonts untouched.
        return face, false
    end
    -- We have bold requested, and a regular/non-bold font.
    if not self.use_bold_font_for_bold then
        -- If promotion to real bold is not wished, force synth bold
        bold = Font.FORCE_SYNTHETIZED_BOLD
    end
    if bold ~= Font.FORCE_SYNTHETIZED_BOLD then
        -- See if a bold font file exists for that regular font.
        local bold_variant_name = self:getBoldVariantName(face.realname)
        if bold_variant_name then
            face = Font:getFace(bold_variant_name, face.orig_size)
            -- It has is_real_bold=true: no adjustment needed
            return face, true
        end
    end
    -- Only the regular font is available, and bold requested:
    -- we'll have synthesized bold - but _getFallbackFont() should
    -- build a list of fallback fonts either synthesized, or possibly
    -- using the bold variant of a regular fallback font.
    -- We don't want to collide with the regular font face_obj.fallbacks
    -- so let's make a shallow clone of this face_obj, and have it cached.
    -- (Different hash if real bold accepted or not, as the fallback
    -- fonts list may then be different.)
    local hash = face.hash..(bold == Font.FORCE_SYNTHETIZED_BOLD and "synthbold" or "realbold")
    local face_obj = self.faces[hash]
    if face_obj then
        return face_obj, bold
    end
    face_obj = {
        orig_font = face.orig_font,
        realname = face.realname,
        size = face.size,
        orig_size = face.orig_size,
        -- We can keep the same FT object and the same hash in this face_obj
        -- (which is only used to identify cached glyphs, that we don't need
        -- to distinguish as "bold" is appended when synthesized as bold)
        ftsize = face.ftsize,
        hash = face.hash,
        hb_features = face.hb_features,
        is_real_bold = nil,
        wants_bold = bold, -- true or Font.FORCE_SYNTHETIZED_BOLD, used
                           -- to pick the appropriate fallback fonts
    }
    face_obj.getFallbackFont = function(num)
        return _getFallbackFont(face_obj, num)
    end
    self.faces[hash] = face_obj
    return face_obj, bold
end

return Font
