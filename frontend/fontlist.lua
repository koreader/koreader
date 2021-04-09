local CanvasContext = require("document/canvascontext")
local DataStorage = require("datastorage")
local FT = require("ffi/freetype")
local HB = require("ffi/harfbuzz")
local Persist = require("persist")
local util = require("util")
local logger = require("logger")
local dbg = require("dbg")

local FontList = {
    fontdir = "./fonts",
    cachedir = DataStorage:getDataDir() .. "/cache/fontlist", -- in a subdirectory, so as not to mess w/ the Cache module.
    fontlist = {},
    fontinfo = {},
    fontnames = {},
}

--[[
These non-LGC Kindle system fonts fail CRe's moronic header check.
Also applies to a number of LGC fonts that have different family names for different styles...
(Those are actually "fixed" via FontConfig in the stock system).
--]]
local kindle_fonts_blacklist = {
    ["DiwanMuna-Bold.ttf"] = true,
    ["DiwanMuna-Regular.ttf"] = true,
    ["HYGothicBold.ttf"] = true,
    ["HYGothicMedium.ttf"] = true,
    ["HYMyeongJoBold.ttf"] = true,
    ["HYMyeongJoMedium.ttf"] = true,
    ["KindleBlackboxBoldItalic.ttf"] = true,
    ["KindleBlackboxBold.ttf"] = true,
    ["KindleBlackboxItalic.ttf"] = true,
    ["KindleBlackboxRegular.ttf"] = true,
    ["Kindle_MonospacedSymbol.ttf"] = true,
    ["Kindle_Symbol.ttf"] = true,
    ["MTChineseSurrogates.ttf"] = true,
    ["MYingHeiTBold.ttf"] = true,
    ["MYingHeiTMedium.ttf"] = true,
    ["NotoNaskhArabicUI-Bold.ttf"] = true,
    ["NotoNaskhArabicUI-Regular.ttf"] = true,
    ["NotoNaskh-Bold.ttf"] = true,
    ["NotoNaskh-Regular.ttf"] = true,
    ["NotoSansBengali-Regular.ttf"] = true,
    ["NotoSansDevanagari-Regular.ttf"] = true,
    ["NotoSansGujarati-Regular.ttf"] = true,
    ["NotoSansKannada-Regular.ttf"] = true,
    ["NotoSansMalayalam-Regular.ttf"] = true,
    ["NotoSansTamil-Regular.ttf"] = true,
    ["NotoSansTelugu-Regular.ttf"] = true,
    ["SakkalKitab-Bold.ttf"] = true,
    ["SakkalKitab-Regular.ttf"] = true,
    ["SongTBold.ttf"] = true,
    ["SongTMedium.ttf"] = true,
    ["STHeitiBold.ttf"] = true,
    ["STHeitiMedium.ttf"] = true,
    ["STSongBold.ttf"] = true,
    ["STSongMedium.ttf"] = true,
    ["TBGothicBold_213.ttf"] = true,
    ["TBGothicMed_213.ttf"] = true,
    ["TBMinchoBold_213.ttf"] = true,
    ["TBMinchoMedium_213.ttf"] = true,
    ["STKaiMedium.ttf"] = true,
    ["Amazon-Ember-Bold.ttf"] = false,
    ["Amazon-Ember-BoldItalic.ttf"] = false,
    ["Amazon-Ember-Heavy.ttf"] = true,
    ["Amazon-Ember-HeavyItalic.ttf"] = true,
    ["Amazon-Ember-Medium.ttf"] = true,
    ["Amazon-Ember-MediumItalic.ttf"] = true,
    ["Amazon-Ember-Regular.ttf"] = false,
    ["Amazon-Ember-RegularItalic.ttf"] = false,
    ["AmazonEmberBold-Bold.ttf"] = true,
    ["AmazonEmberBold-BoldItalic.ttf"] = true,
    ["AmazonEmberBold-Italic.ttf"] = true,
    ["AmazonEmberBold-Regular.ttf"] = true,
    ["Caecilia_LT_65_Medium.ttf"] = false,
    ["Caecilia_LT_66_Medium_Italic.ttf"] = false,
    ["Caecilia_LT_75_Bold.ttf"] = false,
    ["Caecilia_LT_76_Bold_Italic.ttf"] = false,
    ["Caecilia_LT_67_Cond_Medium.ttf"] = true,
    ["Caecilia_LT_68_Cond_Medium_Italic.ttf"] = true,
    ["Caecilia_LT_77_Cond_Bold.ttf"] = true,
    ["Caecilia_LT_78_Cond_Bold_Italic.ttf"] = true,
    ["Futura-Bold.ttf"] = true,
    ["Futura-BoldOblique.ttf"] = true,
    ["Helvetica_LT_65_Medium.ttf"] = true,
    ["Helvetica_LT_66_Medium_Italic.ttf"] = true,
    ["Helvetica_LT_75_Bold.ttf"] = true,
    ["Helvetica_LT_76_Bold_Italic.ttf"] = true,
}

local function isInFontsBlacklist(f)
    -- write test for this
    return CanvasContext.isKindle() and kindle_fonts_blacklist[f]
end

local function getExternalFontDir()
    if CanvasContext.isAndroid() or
        CanvasContext.isDesktop() or
        CanvasContext.isEmulator() or
        CanvasContext.isPocketBook()
    then
        return require("frontend/ui/elements/font_settings"):getPath()
    else
        return os.getenv("EXT_FONT_DIR")
    end
end

-- Query FreeType/HarfBuzz about font metadata
local function collectFaceInfo(path)
    local res = {}
    local n = FT.getFaceCount(path)
    if not n then
        return
    end
    for i=0, n-1 do
        local ok, face = pcall(FT.newFace, path, nil, i)
        if not ok then
            return nil
        end

        -- If family_name is missing, it's probably too broken to be useful
        if face.family_name ~= nil then
            local fres = face:getInfo()
            local hbface = HB.hb_ft_face_create_referenced(face)
            fres.names = hbface:getNames()
            fres.scripts, fres.langs = hbface:getCoverage()
            fres.path = path
            fres.index = i
            table.insert(res, fres)
            hbface:destroy()
        end
        face:done()
    end
    return res
end

local font_exts = {
    ["ttf"] = true,
    ["ttc"] = true,
    ["cff"] = true,
    ["otf"] = true,
}

function FontList:_readList(dir, mark)
    util.findFiles(dir, function(path, file, attr)
        -- See if we're interested
        if file:sub(1,1) == "." then return end
        local file_type = file:lower():match(".+%.([^.]+)") or ""
        if not font_exts[file_type] then return end

        -- Add it to the list
        if not isInFontsBlacklist(file) then
            table.insert(self.fontlist, path)
        end

        -- And into cached info table
        mark[path] = true
        if self.fontinfo[path] and (self.fontinfo[path].change == attr.change) then
            return
        end
        local fi = collectFaceInfo(path)
        if not fi then return end
        fi.change = attr.change
        self.fontinfo[path] = fi
        mark.cache_dirty = true
    end)
end

function FontList:getFontList()
    if #self.fontlist > 0 then return self.fontlist end

    local cache = Persist:new{
        path = self.cachedir .. "/fontinfo.dat"
    }

    local t, err = cache:load()
    if not t then
        logger.info(cache.path, err, "initializing it")

        -- Create new subdirectory
        lfs.mkdir(self.cachedir)
    end
    self.fontinfo = t or {}

    -- used for marking fonts we're seeing
    local mark = { cache_dirty = false }

    self:_readList(self.fontdir, mark)
    -- multiple paths should be joined with semicolon
    for dir in string.gmatch(getExternalFontDir() or "", "([^;]+)") do
        self:_readList(dir, mark)
    end

    -- clear fonts that no longer exist
    for k, _ in pairs(self.fontinfo) do
        if not mark[k] then
            self.fontinfo[k] = nil
            mark.cache_dirty = true
        end
    end

    if dbg.is_verbose then
        -- when verbose debug is on, always dump the cache in plain text (to inspect the db output)
        cache:save(self.fontinfo)
    elseif mark.cache_dirty then
        -- otherwise dump the db in binary (more compact), and only if something has changed
        cache:save(self.fontinfo, true)
    end

    local names = self.fontnames
    for _,coll in pairs(self.fontinfo) do
        for _,v in ipairs(coll) do
            local nlist = names[v.name] or {}
            assert(v.name)
            if #nlist == 0 then
                logger.dbg("FONTNAMES ADD: ", v.name)
            end
            names[v.name] = nlist
            table.insert(nlist, v)
        end
    end

    table.sort(self.fontlist)
    return self.fontlist
end

-- Try to determine the localized font name
function FontList:getLocalizedFontName(file, index)
    local lang = G_reader_settings:readSetting("language")
    if not lang then return end
    lang = lang:lower():gsub("_","-")
    local altname = self.fontinfo[file]
    altname = altname and altname[index+1]
    altname = altname and altname.names and (altname.names[lang] or altname.names[lang:match("%w+")])
    altname = altname and (altname[tonumber(HB.HB_OT_NAME_ID_FULL_NAME)] or altname[tonumber(HB.HB_OT_NAME_ID_FONT_FAMILY)])
    if not altname then return end -- ensure nil
    return altname
end

return FontList
