-- high level wrapper module for gettext

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")

Language = {}

function Language:changeLanguage(lang_po)
	_.changeLang(lang_po)
	G_reader_settings:saveSetting("language_po", lang_po)
	UIManager:show(InfoMessage:new{
		text = _("Please restart reader for new language setting to take effect."),
		timeout = 3,
	})
end

function Language:genLanguageSubItem(lang, lang_po)
	return {
		text = lang,
		callback = function()
			self:changeLanguage(lang_po)
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
				self:genLanguageSubItem("čeština", "cs_CZ"),
				self:genLanguageSubItem("Deutsch", "de"),
				self:genLanguageSubItem("français", "fr"),
				--self:genLanguageSubItem("magyar", "hu"),
				self:genLanguageSubItem("Italiano", "it_IT"),
				self:genLanguageSubItem("język polski", "pl"),
				self:genLanguageSubItem("Português do Brasil", "pt_BR"),
				self:genLanguageSubItem("Русский язык", "ru"),
				--self:genLanguageSubItem("svenska", "sv"),
				self:genLanguageSubItem("Türkçe", "tr"),
				--self:genLanguageSubItem("Tiếng Việt", "vi"),
				self:genLanguageSubItem("简体中文", "zh_CN"),
			}
		}
	end
	return self.LangMenuTable
end

return Language
