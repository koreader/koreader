-- high level wrapper module for gettext

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")

local Language = {}

function Language:changeLanguage(lang_locale)
    _.changeLang(lang_locale)
    G_reader_settings:saveSetting("language", lang_locale)
    UIManager:show(InfoMessage:new{
        text = _("Please restart KOReader for the new language setting to take effect."),
        timeout = 3,
    })
end

function Language:genLanguageSubItem(lang, lang_locale)
    return {
        text = lang,
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
                self:genLanguageSubItem("English", "C"),
                self:genLanguageSubItem("Catalá", "ca"),
                self:genLanguageSubItem("Čeština", "cs_CZ"),
                self:genLanguageSubItem("Deutsch", "de"),
                self:genLanguageSubItem("Español", "es"),
                self:genLanguageSubItem("Français", "fr"),
                self:genLanguageSubItem("Galego", "gl"),
                self:genLanguageSubItem("Italiano", "it_IT"),
                self:genLanguageSubItem("Magyar", "hu"),
                self:genLanguageSubItem("Nederlands", "nl_NL"),
                self:genLanguageSubItem("Polski", "pl"),
                self:genLanguageSubItem("Português do Brasil", "pt_BR"),
                -- self:genLanguageSubItem("Svenska", "sv"),
                -- self:genLanguageSubItem("Tiếng Việt", "vi"),
                self:genLanguageSubItem("Türkçe", "tr"),
                -- self:genLanguageSubItem("Viet Nam", "vi_VN"),
                self:genLanguageSubItem("Русский язык", "ru"),
                self:genLanguageSubItem("Українська", "uk"),
                self:genLanguageSubItem("简体中文", "zh_CN"),
                self:genLanguageSubItem("한글", "ko_KR"),
            }
        }
    end
    return self.LangMenuTable
end

return Language
