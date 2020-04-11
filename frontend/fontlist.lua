local CanvasContext = require("document/canvascontext")

local FontList = {
    fontdir = "./fonts",
    fontlist = {},
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
    if CanvasContext.isAndroid() or CanvasContext.isDesktop() or CanvasContext.isEmulator() then
        return require("frontend/ui/elements/font_settings"):getPath()
    else
        return os.getenv("EXT_FONT_DIR")
    end
end

local function _readList(target, dir)
    -- lfs.dir non-existent directory will give an error, weird!
    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if not ok then return end
    for f in iter, dir_obj do
        local mode = lfs.attributes(dir.."/"..f, "mode")
        if mode == "directory" and f ~= "." and f ~= ".." then
            _readList(target, dir.."/"..f)
        elseif mode == "file" or mode == "link" then
            if string.sub(f, 1, 1) ~= "." then
                local file_type = string.lower(string.match(f, ".+%.([^.]+)") or "")
                if file_type == "ttf" or file_type == "ttc"
                    or file_type == "cff" or file_type == "otf" then
                    if not isInFontsBlacklist(f) then
                        table.insert(target, dir.."/"..f)
                    end
                end
            end
        end
    end
end

function FontList:getFontList()
    if #self.fontlist > 0 then return self.fontlist end
    _readList(self.fontlist, self.fontdir)
    -- multiple paths should be joined with semicolon
    for dir in string.gmatch(getExternalFontDir() or "", "([^;]+)") do
        _readList(self.fontlist, dir)
    end
    table.sort(self.fontlist)
    return self.fontlist
end

return FontList
