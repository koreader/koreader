local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local JSON = require("json")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local T = require("ffi/util").template
local _ = require("gettext")
local util = require("util")

local ReaderHyphenation = InputContainer:new{
    hyph_menu_title = _("Hyphenation"),
    hyph_table = nil,
}

function ReaderHyphenation:init()
    self.lang_table = {}
    self.hyph_table = {}
    self.hyph_alg = cre.getSelectedHyphDict()

    local lang_data_file = assert(io.open("./data/hyph/languages.json"), "r")
    local ok, lang_data = pcall(JSON.decode, lang_data_file:read("*all"))

    if ok and lang_data then
        for k,v in ipairs(lang_data) do
            table.insert(self.hyph_table, {
                text = v.name,
                callback = function()
                    self.hyph_alg = v.filename
                    UIManager:show(InfoMessage:new{
                        text = T(_("Changed hyphenation to %1."), v.name),
                    })
                    self.ui.document:setHyphDictionary(v.filename)
                    self.ui.toc:onUpdateToc()
                end,
                hold_callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = T( _("Set fallback hyphenation to %1?"), v.name),
                        ok_callback = function()
                            G_reader_settings:saveSetting("hyph_alg_fallback", v.filename)
                        end,
                    })
                end,
                checked_func = function()
                    return v.filename == self.hyph_alg
                end
            })

            self.lang_table[v.language] = v.filename
            if v.aliases then
                for i,alias in ipairs(v.aliases) do
                    self.lang_table[alias] = v.filename
                end
            end
        end
    end
    self.ui.menu:registerToMainMenu(self)
end

function ReaderHyphenation:parseLanguageTag(lang_tag)
    -- Parse an RFC 5646 language tag, like "en-US" or "en".
    -- https://tools.ietf.org/html/rfc5646

    -- We are only interested in the language and region parts.
    local language = nil
    local region = nil

    for part in util.gsplit(lang_tag, "-", false) do
        if not language then
            language = string.lower(part)
        elseif string.len(part) == 2 and not string.match(part, "[^%a]") then
            region = string.upper(part)
        end
    end
    return language, region
end

function ReaderHyphenation:getDictForLanguage(lang_tag)
    -- EPUB language is an RFC 5646 language tag.
    -- http://www.idpf.org/epub/301/spec/epub-publications.html#sec-opf-dclanguage
    --
    -- FB2 language is a two-letter language code
    -- (which is also a valid RFC 5646 language tag).
    -- http://fictionbook.org/index.php/%D0%AD%D0%BB%D0%B5%D0%BC%D0%B5%D0%BD%D1%82_lang (in Russian)

    local language, region = self:parseLanguageTag(lang_tag)
    if not language then
        return
    end

    local dict
    if region then
        dict = self.lang_table[language .. '-' .. region]
    end
    if not dict then
        dict = self.lang_table[language]
    end
    return dict
end
function ReaderHyphenation:onPreRenderDocument(config)
    -- This is called after the document has been loaded
    -- so we can use the document language.

    local hyph_alg = config:readSetting("hyph_alg")
    if not hyph_alg then
        hyph_alg = self:getDictForLanguage(self.ui.document:getProps().language)
    end
    if not hyph_alg then
        hyph_alg = G_reader_settings:readSetting("hyph_alg_fallback")
    end
    if hyph_alg then
        self.ui.document:setHyphDictionary(hyph_alg)
    end
    self.hyph_alg = cre.getSelectedHyphDict()
end

function ReaderHyphenation:onSaveSettings()
    self.ui.doc_settings:saveSetting("hyph_alg", self.hyph_alg)
end

function ReaderHyphenation:addToMainMenu(tab_item_table)
    -- insert table to main reader menu
    table.insert(tab_item_table.typeset, {
        text = self.hyph_menu_title,
        sub_item_table = self.hyph_table,
    })
end

return ReaderHyphenation
