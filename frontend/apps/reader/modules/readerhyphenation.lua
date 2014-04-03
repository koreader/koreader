local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")

local ReaderHyphenation = InputContainer:new{
    hyph_menu_title = _("Hyphenation"),
    hyph_table = nil,
    cur_hyph_idx = nil,
}

function ReaderHyphenation:_changeSel(k)
    if self.cur_hyph_idx then
        self.hyph_table[self.cur_hyph_idx].selected = false
    end
    self.hyph_table[k].selected = true
    self.cur_hyph_idx = k
end

function ReaderHyphenation:init()
    self.hyph_table = {}
    self.hyph_alg = cre.getSelectedHyphDict()
    for k,v in ipairs(cre.getHyphDictList()) do
        if v == self.hyph_alg then
            self.cur_hyph_idx = k
        end
        table.insert(self.hyph_table, {
            text = v,
            callback = function()
                self.hyph_alg = v
                UIManager:show(InfoMessage:new{
                    text = _("Change Hyphenation to ")..v,
                })
                self:_changeSel(k)
                cre.setHyphDictionary(v)
            end
        })
    end
    self.ui.menu:registerToMainMenu(self)
end

function ReaderHyphenation:onReadSettings(config)
    local hyph_alg = config:readSetting("hyph_alg")
    if hyph_alg then
        cre.setHyphDictionary(hyph_alg)
    end
    self.hyph_alg = cre.getSelectedHyphDict()
    for k,v in ipairs(self.hyph_table) do
        if v.text == self.hyph_alg then
            self:_changeSel(k)
        end
    end
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
