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
        [3] = "freefont/FreeSans.ttf",
        [4] = "freefont/FreeSerif.ttf",
        [5] = "DroidSansFallback.ttf", -- for some ancient pre-4.4 Androids
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
        local builtin_font_location = FontList.fontdir.."/"..realname
        local ok, face = pcall(Freetype.newFace, builtin_font_location, size)

        -- We don't ship Droid and Noto on Android because they're system fonts.
        -- This cuts package size in half, but 4.4 and older systems
        -- might not ship Noto.
        if not ok and is_android and realname:match("^Noto") then
            local system_font_location = "/system/fonts"
            logger.dbg("Font:", realname, "not found. Trying system location.")

            ok, face = pcall(Freetype.newFace, system_font_location.."/"..realname, size)

            -- Relevant Noto font not found on this device, fall back to Droid
            if not ok then
                if realname:match("Bold") then
                    realname = "DroidSans-Bold.ttf"
                else
                    realname = "DroidSans.ttf"
                end
            end
        end

        -- Not all fonts are bundled on all platforms because they come with the system.
        -- In that case, search through all font folders for the requested font.
        if not ok and font ~= realname then
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
