local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local T = require("ffi/util").template
local _ = require("gettext")

local ReaderHyphenation = InputContainer:new{
    hyph_menu_title = _("Hyphenation"),
    hyph_table = nil,
}

function ReaderHyphenation:init()
    self.hyph_table = {}
    self.hyph_alg = cre.getSelectedHyphDict()
    for k,v in ipairs(cre.getHyphDictList()) do
        table.insert(self.hyph_table, {
            text = v,
            callback = function()
                self.hyph_alg = v
                UIManager:show(InfoMessage:new{
                    text = T( _("Changed hyphenation to %1."), v),
                })
                self.ui.document:setHyphDictionary(v)
                self.ui.toc:onUpdateToc()
            end,
            checked_func = function()
                return v == self.hyph_alg
            end
        })
    end
    self.ui.menu:registerToMainMenu(self)
end

function ReaderHyphenation:onReadSettings(config)
    local hyph_alg = config:readSetting("hyph_alg")
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
