local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local JSON = require("json")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local UIManager = require("ui/uimanager")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

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
                    self.ui.doc_settings:saveSetting("hyph_alg", self.hyph_alg)
                    UIManager:show(InfoMessage:new{
                        text = T(_("Changed hyphenation to %1."), v.name),
                    })
                    self.ui.document:setHyphDictionary(v.filename)
                    self.ui.toc:onUpdateToc()
                end,
                hold_callback = function()
                    UIManager:show(MultiConfirmBox:new{
                        -- No real need for a way to remove default one, we can just
                        -- toggle between setting a default OR a fallback (if a default
                        -- one is set, no fallback will ever be used - if a fallback one
                        -- is set, no default is wanted; so when we set one below, we
                        -- remove the other).
                        text = T( _("Set default or fallback hyphenation pattern to %1?\nDefault will always take precedence while fallback will only be used if the language of the book can't be automatically determined."), v.name),
                        choice1_text = _("Default"),
                        choice1_callback = function()
                            G_reader_settings:saveSetting("hyph_alg_default", v.filename)
                            G_reader_settings:delSetting("hyph_alg_fallback")
                        end,
                        choice2_text = _("Fallback"),
                        choice2_callback = function()
                            G_reader_settings:saveSetting("hyph_alg_fallback", v.filename)
                            G_reader_settings:delSetting("hyph_alg_default")
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

    -- Use the one manually set for this document
    local hyph_alg = config:readSetting("hyph_alg")
    if not hyph_alg then -- If none, use the one manually set as default (with Hold)
        hyph_alg = G_reader_settings:readSetting("hyph_alg_default")
    end
    if not hyph_alg then -- If none, use the one associated with document's language
        hyph_alg = self:getDictForLanguage(self.ui.document:getProps().language)
    end
    if not hyph_alg then -- If none, use the one manually set as fallback (with Hold)
        hyph_alg = G_reader_settings:readSetting("hyph_alg_fallback")
    end
    if hyph_alg then
        self.ui.document:setHyphDictionary(hyph_alg)
    end
    -- If we haven't set any, hardcoded English_US_hyphen_(Alan).pdb (in cre.cpp) will be used
    self.hyph_alg = cre.getSelectedHyphDict()
end

function ReaderHyphenation:addToMainMenu(menu_items)
    -- insert table to main reader menu
    menu_items.hyphenation = {
        text = self.hyph_menu_title,
        sub_item_table = self.hyph_table,
    }
end

return ReaderHyphenation
