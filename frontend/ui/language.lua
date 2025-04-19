-- high level wrapper module for gettext

local _ = require("gettext")

local Language = {
    language_names = {
        C = "English",
        en = "English",
        en_GB = "English (United Kingdom)",
        ca = "Catalá",
        cs = "Čeština",
        da = "Dansk",
        de = "Deutsch",
        eo = "Esperanto",
        es = "Español",
        eu = "Euskara",
        fi = "Suomi",
        fr = "Français",
        gl = "Galego",
        it_IT = "Italiano",
        he = "עִבְרִית",
        hr = "Hrvatski",
        hu = "Magyar",
        lt_LT = "Lietuvių",
        lv = "Latviešu",
        nl_NL = "Nederlands",
        nb_NO = "Norsk bokmål",
        pl = "Polski",
        pl_PL = "Polski2",
        pt_PT = "Português",
        pt_BR = "Português do Brasil",
        ro = "Română",
        ro_MD = "Română (Moldova)",
        sk = "Slovenčina",
        sv = "Svenska",
        th = "ภาษาไทย",
        vi = "Tiếng Việt",
        tr = "Türkçe",
        vi_VN = "Viet Nam",
        ar = "عربى",
        bg_BG = "български",
        bn = "বাংলা",
        el = "Ελληνικά",
        fa = "فارسی",
        hi = "हिन्दी",
        ja = "日本語",
        ka = "ქართული",
        kk = "Қазақ",
        ko_KR = "한국어",
        ru = "Русский",
        sr = "Српски",
        uk = "Українська",
        zh = "中文",
        zh_CN = "简体中文",
        zh_TW = "中文（台灣)",
        ["zh_TW.Big5"] = "中文（台灣）（Big5）",
    },
    -- Languages that are written RTL, and should have the UI mirrored.
    -- Should match lang tags defined in harfbuzz/src/hb-ot-tag-table.hh.
    -- https://meta.wikimedia.org/wiki/Template:List_of_language_names_ordered_by_code
    -- Not included are those absent or commented out in hb-ot-tag-table.hh.
    languages_rtl = {
        ar  = true, -- Arabic
        arz = true, -- Egyptian Arabic
        ckb = true, -- Sorani (Central Kurdish)
        dv  = true, -- Divehi
        fa  = true, -- Persian
        he  = true, -- Hebrew
        ks  = true, -- Kashmiri
        ku  = true, -- Kurdish
        ps  = true, -- Pashto
        sd  = true, -- Sindhi
        ug  = true, -- Uyghur
        ur  = true, -- Urdu
        yi  = true, -- Yiddish
    }
}

function Language:getLanguageName(lang_locale)
    return self.language_names[lang_locale] or lang_locale
end

function Language:isLanguageRTL(lang_locale)
    if not lang_locale then
        return false
    end
    local lang = lang_locale
    local sep = lang:find("_")
    if sep then
        lang = lang:sub(1, sep-1)
    end
    return self.languages_rtl[lang] or false
end

function Language:changeLanguage(lang_locale)
    local UIManager = require("ui/uimanager")
    _.changeLang(lang_locale)
    G_reader_settings:saveSetting("language", lang_locale)
    UIManager:askForRestart(_("Please restart KOReader for the new language setting to take effect."))
end

function Language:genLanguageSubItem(lang_locale)
    return {
        text = self:getLanguageName(lang_locale),
        checked_func = function()
            return G_reader_settings:readSetting("language") == lang_locale
        end,
        callback = function()
            self:changeLanguage(lang_locale)
        end
    }
end

function Language:getLangMenuTable()
    -- cache menu table
    if not self.LangMenuTable then
        self.LangMenuTable = {
            text = _("Language"),
            -- NOTE: language with no translation are commented out for now
            sub_item_table = {
                self:genLanguageSubItem("C"),
                self:genLanguageSubItem("en_GB"),
                self:genLanguageSubItem("ca"),
                self:genLanguageSubItem("cs"),
                self:genLanguageSubItem("de"),
                self:genLanguageSubItem("eo"),
                self:genLanguageSubItem("es"),
                self:genLanguageSubItem("eu"),
                self:genLanguageSubItem("fi"),
                self:genLanguageSubItem("fr"),
                self:genLanguageSubItem("gl"),
                self:genLanguageSubItem("hr"),
                self:genLanguageSubItem("it_IT"),
                self:genLanguageSubItem("hu"),
                self:genLanguageSubItem("lt_LT"),
                self:genLanguageSubItem("lv"),
                self:genLanguageSubItem("nl_NL"),
                self:genLanguageSubItem("nb_NO"),
                self:genLanguageSubItem("pl"),
                --self:genLanguageSubItem("pl_PL"),
                self:genLanguageSubItem("pt_PT"),
                self:genLanguageSubItem("pt_BR"),
                self:genLanguageSubItem("ro"),
                self:genLanguageSubItem("ro_MD"),
                self:genLanguageSubItem("sk"),
                self:genLanguageSubItem("sv"),
                self:genLanguageSubItem("vi"),
                self:genLanguageSubItem("tr"),
                self:genLanguageSubItem("vi_VN"),
                self:genLanguageSubItem("ar"),
                self:genLanguageSubItem("bg_BG"),
                --self:genLanguageSubItem("bn"),
                self:genLanguageSubItem("el"),
                self:genLanguageSubItem("fa"),
                self:genLanguageSubItem("he"),
                self:genLanguageSubItem("hi"),
                self:genLanguageSubItem("ja"),
                self:genLanguageSubItem("ka"),
                --self:genLanguageSubItem("kk"),
                self:genLanguageSubItem("ko_KR"),
                self:genLanguageSubItem("ru"),
                self:genLanguageSubItem("sr"),
                self:genLanguageSubItem("uk"),
                --self:genLanguageSubItem("zh"),
                self:genLanguageSubItem("zh_CN"),
                self:genLanguageSubItem("zh_TW"),
                --self:genLanguageSubItem("zh_TW.Big5"),
            }
        }
    end
    return self.LangMenuTable
end

return Language
