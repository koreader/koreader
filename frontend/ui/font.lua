local lfs = require("libs/libkoreader-lfs")
local Freetype = require("ffi/freetype")
local Screen = require("device").screen
local Device = require("device")
local DEBUG = require("dbg")

local Font = {
    fontmap = {
        -- default font for menu contents
        cfont = "noto/NotoSans-Regular.ttf",
        -- default font for title
        --tfont = "NimbusSanL-BoldItal.cff",
        tfont = "noto/NotoSans-Bold.ttf",
        -- default font for footer
        ffont = "noto/NotoSans-Regular.ttf",

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

        -- font for info messages
        infofont = "noto/NotoSans-Regular.ttf",
    },
    fallbacks = {
        [1] = "noto/NotoSansCJK-Regular.ttf",
        [2] = "noto/NotoSans-Regular.ttf",
        [3] = "freefont/FreeSans.ttf",
    },

    fontdir = "./fonts",

    -- face table
    faces = {},
}


function Font:getFace(font, size)
    -- default to content font
    if not font then font = self.cfont end

    -- original size before scaling by screen DPI
    local orig_size = size
    local size = Screen:scaleBySize(size)

    local hash = font..size
    local face_obj = self.faces[hash]
    -- build face if not found
    if not face_obj then
        local realname = self.fontmap[font]
        if not realname then
            realname = font
        end
        realname = self.fontdir.."/"..realname
        ok, face = pcall(Freetype.newFace, realname, size)
        if not ok then
            DEBUG("#! Font "..font.." ("..realname..") not supported: "..face)
            return nil
        end
        face_obj = {
            size = size,
            orig_size = orig_size,
            ftface = face,
            hash = hash
        }
        self.faces[hash] = face_obj
    -- DEBUG("getFace, found: "..realname.." size:"..size)
    end
    return face_obj
end

function checkfont(f)
    local exclusive_system_font = {
    --these kindle system fonts can not be used by freetype and will give error
        "HYGothicBold.ttf",
        "HYGothicMedium.ttf",
        "HYMyeongJoBold.ttf",
        "HYMyeongJoMedium.ttf",
        "MYingHeiTBold.ttf",
        "MYingHeiTMedium.ttf",
        "SongTBold.ttf",
        "SongTMedium.ttf"
        }
    for _,value in ipairs(exclusive_system_font) do
        if value == f then
            return true
        end
    end
    return false
end

function Font:_readList(target, dir)
    -- lfs.dir non-exsitent directory will give error, weird!
    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if not ok then return end
    for f in iter, dir_obj do
        if lfs.attributes(dir.."/"..f, "mode") == "directory" and f ~= "." and f ~= ".." then
            self:_readList(target, dir.."/"..f)
        else
            local file_type = string.lower(string.match(f, ".+%.([^.]+)") or "")
            if file_type == "ttf" or file_type == "ttc"
                or file_type == "cff" or file_type == "otf" then
                if checkfont(f) ~=true then
                    table.insert(target, dir.."/"..f)
                end
            end
        end
    end
end

function Font:_getExternalFontDir()
    if Device:isAndroid() then
        return ANDROID_FONT_DIR
    else
        return os.getenv("EXT_FONT_DIR")
    end
end

function Font:getFontList()
    local fontlist = {}
    self:_readList(fontlist, self.fontdir)
    -- multiple paths should be joined with semicolon
    for dir in string.gmatch(self:_getExternalFontDir() or "", "([^;]+)") do
        self:_readList(fontlist, dir)
    end
    table.sort(fontlist)
    return fontlist
end

return Font
