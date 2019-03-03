--[[--
Font module.
]]

local Freetype = require("ffi/freetype")
local logger = require("logger")
local Screen = require("device").screen
local FontList = require("fontlist")

local Font = {
    fontmap = {
        -- default font for menu contents
        cfont = "noto/NotoSans-Regular.ttf",
        -- default font for title
        --tfont = "NimbusSanL-BoldItal.cff",
        tfont = "noto/NotoSans-Bold.ttf",
        smalltfont = "noto/NotoSans-Bold.ttf",
        x_smalltfont = "noto/NotoSans-Bold.ttf",
        -- default font for footer
        ffont = "noto/NotoSans-Regular.ttf",
        smallffont = "noto/NotoSans-Regular.ttf",
        largeffont = "noto/NotoSans-Regular.ttf",

        -- default font for reading position info
        rifont = "noto/NotoSans-Regular.ttf",

        -- default font for pagination display
        pgfont = "noto/NotoSans-Regular.ttf",

        -- selectmenu: font for item shortcut
        scfont = "droid/DroidSansMono.ttf",

        -- help page: font for displaying keys
        hpkfont = "droid/DroidSansMono.ttf",
        -- font for displaying help messages
        hfont = "noto/NotoSans-Regular.ttf",

        -- font for displaying input content
        -- we have to use mono here for better distance controlling
        infont = "droid/DroidSansMono.ttf",
        -- small mono font for displaying code
        smallinfont = "droid/DroidSansMono.ttf",

        -- font for info messages
        infofont = "noto/NotoSans-Regular.ttf",

        -- small font for info messages
        smallinfofont = "noto/NotoSans-Regular.ttf",
        -- small bold font for info messages
        smallinfofontbold = "noto/NotoSans-Bold.ttf",
        -- extra small font for info messages
        x_smallinfofont = "noto/NotoSans-Regular.ttf",
        -- extra extra small font for info messages
        xx_smallinfofont = "noto/NotoSans-Regular.ttf",
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
        [1] = "noto/NotoSans-Regular.ttf",
        [2] = "noto/NotoSansCJKsc-Regular.otf",
        [3] = "freefont/FreeSans.ttf",
        [4] = "freefont/FreeSerif.ttf",
    },

    -- face table
    faces = {},
}

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
        realname = FontList.fontdir.."/"..realname
        local ok, face = pcall(Freetype.newFace, realname, size)
        if not ok then
            logger.warn("#! Font ", font, " (", realname, ") not supported: ", face)
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
            size = size,
            orig_size = orig_size,
            ftface = face,
            hash = hash
        }
        self.faces[hash] = face_obj
    end
    return face_obj
end

return Font
