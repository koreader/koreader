local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")

local ReaderHyphenation = InputContainer:new{
	hyph_menu_title = _("Hyphenation"),
	hyph_table = nil,
	cur_hyph_idx = nil,
}

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
				self.cur_hyph_idx = k
				self.hyph_alg = v
				UIManager:show(InfoMessage:new{
					text = _("Change Hyphenation to ")..v,
				})
				self.hyph_table[k].selected = true
				self.hyph_table[self.cur_hyph_idx].selected = false
				cre.setHyphDictionary(v)
			end
		})
	end
	self.ui.menu:registerToMainMenu(self)
end

function ReaderHyphenation:addToMainMenu(tab_item_table)
	-- insert table to main reader menu
	table.insert(tab_item_table.typeset, {
		text = self.hyph_menu_title,
		sub_item_table = self.hyph_table,
	})
end

return ReaderHyphenation
