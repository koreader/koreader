local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Menu = require("ui/widget/menu")
local Screen = require("ui/screen")
local Device = require("ui/device")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local _ = require("gettext")

local ReaderToc = InputContainer:new{
	toc = nil,
	toc_menu_title = _("Table of contents"),
}

function ReaderToc:init()
	if Device:hasKeyboard() then
		self.key_events = {
			ShowToc = {
				{ "T" },
				doc = _("show Table of Content menu") },
		}
	end
	self.ui.menu:registerToMainMenu(self)
end

function ReaderToc:cleanUpTocTitle(title)
	return (title:gsub("\13", ""))
end

function ReaderToc:onSetDimensions(dimen)
	self.dimen = dimen
end

function ReaderToc:onUpdateToc()
	self.toc = nil
	return true
end

function ReaderToc:fillToc()
	self.toc = self.ui.document:getToc()
end

-- _getTocTitleByPage wrapper, so specific reader
-- can tranform pageno according its need
function ReaderToc:getTocTitleByPage(pn_or_xp)
	local page = pn_or_xp
	if type(pn_or_xp) == "string" then
		page = self.ui.document:getPageFromXPointer(pn_or_xp)
	end
	return self:_getTocTitleByPage(page)
end

function ReaderToc:_getTocTitleByPage(pageno)
	if not self.toc then
		-- build toc when needed.
		self:fillToc()
	end

	-- no table of content
	if #self.toc == 0 then
		return ""
	end

	local pre_entry = self.toc[1]
	for _k,_v in ipairs(self.toc) do
		if _v.page > pageno then
			break
		end
		pre_entry = _v
	end
	return self:cleanUpTocTitle(pre_entry.title)
end

function ReaderToc:getTocTitleOfCurrentPage()
	return self:getTocTitleByPage(self.pageno)
end

function ReaderToc:onShowToc()
	if not self.toc then
		self:fillToc()
	end
	-- build menu items
	if #self.toc > 0 and not self.toc[1].text then
		for _,v in ipairs(self.toc) do
			v.text = ("        "):rep(v.depth-1)..self:cleanUpTocTitle(v.title)
		end
	end

	local menu_container = CenterContainer:new{
		dimen = Screen:getSize(),
	}

	local toc_menu = Menu:new{
		title = _("Table of Contents"),
		item_table = self.toc,
		ui = self.ui,
		width = Screen:getWidth()-50,
		height = Screen:getHeight()-50,
		show_parent = menu_container,
	}

	table.insert(menu_container, toc_menu)

	function toc_menu:onMenuChoice(item)
		self.ui:handleEvent(Event:new("PageUpdate", item.page))
	end

	toc_menu.close_callback = function()
		UIManager:close(menu_container)
	end

	UIManager:show(menu_container)
	return true
end

function ReaderToc:addToMainMenu(tab_item_table)
	-- insert table to main reader menu
	table.insert(tab_item_table.navi, {
		text = self.toc_menu_title,
		callback = function()
			self:onShowToc()
		end,
	})
end

return ReaderToc
